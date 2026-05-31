/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import SwiftUI

/// Closed-notch live activity shown when one of the monitored messaging
/// apps (WhatsApp / Teams / Slack / iMessage / Discord) has unread.
///
/// Layout mirrors `CodingAgentAttentionLiveActivity` and Atoll's
/// `MusicLiveActivity`: 3-section HStack derived from
/// `vm.effectiveClosedNotchHeight` so the notch silhouette stays intact
/// and hover-to-open keeps working. All inner views set
/// `.allowsHitTesting(false)`.
///
/// Shows the app with the highest unread count on the left and a numeric
/// badge on the right. When several apps have unread, an overflow `+N`
/// is appended to the count badge so the user knows there's more.
struct MessagingLiveActivity: View {
    @ObservedObject var monitor: MessagingAppMonitor
    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var pulse = false
    /// "Just arrived" scale-puff state. Triggered on first appear AND
    /// whenever the leading app's count increases, so a fresh message
    /// re-pulses the indicator even if one was already on screen.
    @State private var puff: CGFloat = 1.0
    @State private var lastTotal: Int = 0

    private var leadingApp: (app: MessagingApp, count: Int)? {
        monitor.unreadSorted.first
    }

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var wingWidth: CGFloat { notchContentHeight }
    private var rightWingWidth: CGFloat { notchContentHeight + 12 }
    private var centerWidth: CGFloat { max(vm.closedNotchSize.width, 96) }

    var body: some View {
        if let leading = leadingApp {
            HStack(spacing: 0) {
                leftBadge(for: leading.app)
                    .frame(width: wingWidth, height: notchContentHeight)

                Rectangle()
                    .fill(.black)
                    .frame(width: centerWidth, height: notchContentHeight)
                    .allowsHitTesting(false)

                rightCount(total: leading.count, hasOverflow: monitor.unreadCounts.count > 1)
                    .frame(width: rightWingWidth, height: notchContentHeight)
            }
            .scaleEffect(puff)
            .onAppear {
                pulse = true
                lastTotal = monitor.totalUnread
                triggerPuff()
            }
            .onChange(of: monitor.totalUnread) { _, newValue in
                // Only puff on increase — going down (resolution) shouldn't
                // re-pulse since that's the "good news" direction.
                if newValue > lastTotal {
                    triggerPuff()
                }
                lastTotal = newValue
            }
        } else {
            EmptyView()
        }
    }

    /// Visual "ping" — scales the indicator up to 1.18x then back to 1.0
    /// over 700 ms with a spring. Communicates "something just landed".
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

    // MARK: Left — leading app icon

    @ViewBuilder
    private func leftBadge(for app: MessagingApp) -> some View {
        let brand = Color(isleHex: app.brandColorHex)
        let badgeSize = notchContentHeight * 0.78
        ZStack {
            // Soft brand-color glow that breathes — same visual cadence
            // as the coding-agents attention badge so the two surfaces
            // feel like part of the same Isle vocabulary.
            RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous)
                .fill(brand)
                .frame(width: badgeSize + 4, height: badgeSize + 4)
                .blur(radius: 4)
                .opacity(pulse ? 0.75 : 0.35)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)

            // Custom asset if the user shipped one, otherwise a brand
            // square with an SF Symbol fallback.
            if NSImage(named: app.iconAssetName) != nil {
                Image(app.iconAssetName)
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
                        Image(systemName: app.fallbackSymbol)
                            .font(.system(size: badgeSize * 0.5, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: brand.opacity(0.4), radius: 3, y: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Right — unread count

    @ViewBuilder
    private func rightCount(total: Int, hasOverflow: Bool) -> some View {
        let brand = leadingApp.map { Color(isleHex: $0.app.brandColorHex) } ?? .gray
        let displayText: String = {
            let head = total > 99 ? "99+" : "\(total)"
            return hasOverflow ? "\(head)+" : head
        }()

        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(brand)
                .overlay(
                    Text(displayText)
                        .font(.system(size: notchContentHeight * 0.42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                )
                .frame(height: notchContentHeight * 0.62)
                .fixedSize()
                .padding(.trailing, 6)
                .shadow(color: brand.opacity(0.45), radius: 4, y: 1)
        }
        .allowsHitTesting(false)
    }
}
