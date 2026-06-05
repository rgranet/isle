/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import IsleCore
import SwiftUI

/// Closed-notch live activity shown when at least one coding-agent session
/// is waiting for user attention (permission request, question, etc.).
///
/// Layout: 3-section HStack mirroring `MusicLiveActivity` so the notch
/// silhouette stays intact and hover-to-open still works.
///   • LEFT wing  — brand-color rounded square with the agent's letter,
///                  big enough to read at notch size
///   • CENTER     — black notch silhouette (no content)
///   • RIGHT wing — a brand-tinted "bell.badge.fill" that pulses softly
///                  so the user understands "something is waiting"
///
/// Critical: every inner view uses `.allowsHitTesting(false)` so the
/// hover-open detection layer above keeps receiving events.
struct CodingAgentAttentionLiveActivity: View {
    @ObservedObject var store: AgentSessionStore
    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var pulse: Bool = false
    /// "Just arrived" scale-puff state. Triggered on first appear AND
    /// whenever the count of attention-requiring sessions increases,
    /// so a fresh permission request re-pulses even if one was already
    /// on screen.
    @State private var puff: CGFloat = 1.0
    @State private var lastAttentionCount: Int = 0

    private var attentionSession: AgentSession? {
        store.sessions.first { $0.phase.requiresAttention }
    }

    private var attentionCount: Int {
        store.sessions.filter { $0.phase.requiresAttention }.count
    }

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var wingWidth: CGFloat { notchContentHeight }
    private var rightWingWidth: CGFloat { notchContentHeight + 6 }
    private var centerWidth: CGFloat { max(vm.closedNotchSize.width, 96) }

    var body: some View {
        if let session = attentionSession {
            HStack(spacing: 0) {
                leftBadge(for: session)
                    .frame(width: wingWidth, height: notchContentHeight)

                Rectangle()
                    .fill(.black)
                    .frame(width: centerWidth, height: notchContentHeight)
                    .allowsHitTesting(false)

                rightSignal(for: session)
                    .frame(width: rightWingWidth, height: notchContentHeight)
            }
            // Pin to the full notch height and center, exactly like
            // MusicLiveActivity / TimerLiveActivity. Without this the
            // activity only claims `notchContentHeight` (= full − 12) and
            // floats with a black gap instead of filling the notch.
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
            .scaleEffect(puff)
            .onAppear {
                pulse = true
                lastAttentionCount = attentionCount
                triggerPuff()
            }
            .onChange(of: attentionCount) { _, newValue in
                if newValue > lastAttentionCount {
                    triggerPuff()
                }
                lastAttentionCount = newValue
            }
        } else {
            EmptyView()
        }
    }

    /// Visual "ping" on arrival or count increase. ~700 ms, springy.
    private func triggerPuff() {
        puff = 0.85
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            puff = 1.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                puff = 1.0
            }
        }
    }

    // MARK: Left — agent identity badge

    @ViewBuilder
    private func leftBadge(for session: AgentSession) -> some View {
        let brand = Color(isleHex: session.tool.brandColorHex)
        let badgeSize = notchContentHeight * 0.92
        ZStack {
            // Soft brand-color glow that breathes — the visual "I'm not
            // going away until you handle me" cue.
            RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous)
                .fill(brand)
                .frame(width: badgeSize + 4, height: badgeSize + 4)
                .blur(radius: 4)
                .opacity(pulse ? 0.85 : 0.45)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

            // Use a per-agent icon asset if one has been added to
            // Assets.xcassets (claudeicon, codexicon, cursoricon, …).
            // Falls back to a brand-color rounded square with the first
            // letter of the tool name for agents that don't have an
            // icon shipped yet (Gemini, Kimi, OpenCode, etc.).
            if let assetName = Self.iconAssetName(for: session.tool) {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badgeSize, height: badgeSize)
                    .clipShape(RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous))
                    .shadow(color: brand.opacity(0.4), radius: 3, y: 1)
            } else {
                RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous)
                    .fill(brand)
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(
                        Text(String(session.tool.shortName.prefix(1)))
                            .font(.system(
                                size: badgeSize * 0.62,
                                weight: .heavy,
                                design: .rounded
                            ))
                            .foregroundStyle(.white)
                            .kerning(-0.5)
                    )
                    .shadow(color: brand.opacity(0.4), radius: 3, y: 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// Maps an `AgentTool` to its custom icon asset name in the Xcode
    /// bundle, or `nil` if no icon has been shipped for that tool yet.
    /// Mirrors the asset folder names in `Assets.xcassets/`.
    private static func iconAssetName(for tool: AgentTool) -> String? {
        switch tool {
        case .claudeCode:  return "claudeicon"
        case .codex:       return "codexicon"
        case .cursor:      return "cursoricon"
        case .geminiCLI:   return "geminiicon"
        case.openCode,
             .kimiCLI,
             .qoder,
             .qwenCode,
             .factory,
             .codebuddy:
            return nil
        }
    }

    // MARK: Right — pulsing notification signal

    @ViewBuilder
    private func rightSignal(for session: AgentSession) -> some View {
        let brand = Color(isleHex: session.tool.brandColorHex)
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            ZStack {
                // Outer halo — same breathing pulse so left + right read
                // as a single coordinated indicator.
                Circle()
                    .fill(brand)
                    .frame(width: notchContentHeight * 0.82, height: notchContentHeight * 0.82)
                    .blur(radius: 4)
                    .opacity(pulse ? 0.55 : 0.15)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: signalSymbol(for: session))
                    .font(.system(size: notchContentHeight * 0.58, weight: .bold))
                    .foregroundStyle(brand)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.trailing, 6)
        }
        .allowsHitTesting(false)
    }

    private func signalSymbol(for session: AgentSession) -> String {
        switch session.phase {
        case .waitingForApproval: return "hand.raised.fill"
        case .waitingForAnswer:   return "questionmark.bubble.fill"
        default:                  return "bell.badge.fill"
        }
    }
}
