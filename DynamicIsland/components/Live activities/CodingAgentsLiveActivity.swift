/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import IsleCore
import SwiftUI

/// Closed-notch indicator showing up to 3 colored dots — one per distinct
/// active agent tool — plus a count badge if more are active. When at least
/// one session needs attention (permission / answer waiting), the dots
/// pulse in their brand colour.
struct CodingAgentsLiveActivity: View {
    @ObservedObject var store: AgentSessionStore
    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var pulse = false

    private var dotsToShow: [String] {
        store.brandColors(limit: 3)
    }

    private var overflowCount: Int {
        max(0, distinctToolCount - dotsToShow.count)
    }

    private var distinctToolCount: Int {
        var seen = Set<AgentTool>()
        for s in store.sessions {
            seen.insert(s.tool)
        }
        return seen.count
    }

    private var attentionActive: Bool {
        store.hasAttentionRequest
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(dotsToShow, id: \.self) { hex in
                Circle()
                    .fill(Color(isleHex: hex))
                    .frame(width: 7, height: 7)
                    .scaleEffect(attentionActive && pulse ? 1.35 : 1.0)
                    .opacity(attentionActive && pulse ? 0.6 : 1.0)
                    .animation(
                        attentionActive
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
            }
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: max(20, vm.effectiveClosedNotchHeight - 4))
        .contentShape(Rectangle())
        .onAppear {
            pulse = true
        }
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        if attentionActive {
            return "\(distinctToolCount) coding agents active, one needs attention"
        }
        return "\(distinctToolCount) coding agents active"
    }
}
