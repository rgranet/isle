/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import SwiftUI

/// Closed-notch "grow on arrival" bandeau shown for ~3 seconds when a
/// new agent permission lands. After the auto-hide expires the notch
/// collapses back to the compact `CodingAgentAttentionLiveActivity`.
///
/// 3-section HStack (left wing / centered title / right wing) so the
/// notch silhouette stays intact and hover-to-open isn't blocked. All
/// inner views use `.allowsHitTesting(false)`.
struct CodingAgentArrivedExpandedView: View {
    let brandColorHex: String
    let title: String

    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var pulse = false
    @State private var slid = false

    private var brand: Color { Color(isleHex: brandColorHex) }
    private var contentHeight: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }
    private var wingWidth: CGFloat { contentHeight }
    private var centerWidth: CGFloat { max(vm.closedNotchSize.width, 120) }

    var body: some View {
        HStack(spacing: 0) {
            leftBadge
                .frame(width: wingWidth + 6, height: contentHeight)

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth, height: contentHeight)
                .overlay(alignment: .bottomLeading) {
                    // Single line pinned to the bottom: the visible band
                    // below the hardware cutout is too short for two lines
                    // (the second one used to get clipped by the notch edge).
                    centerLabel
                        .padding(.bottom, 9)
                }
                .allowsHitTesting(false)

            rightSymbol
                .frame(width: wingWidth + 12, height: contentHeight)
        }
        .onAppear {
            pulse = true
            withAnimation(.easeOut(duration: 0.35)) { slid = true }
        }
    }

    // MARK: Left badge — brand-color square taking up most of the wing

    private var leftBadge: some View {
        let badge = contentHeight * 0.82
        return RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous)
            .fill(brand)
            .frame(width: badge, height: badge)
            .overlay(
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: badge * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: brand.opacity(0.5), radius: 4, y: 2)
            .siriGlow(
                brand,
                in: RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous),
                blurRadius: 5,
                opacityRange: 0.5...0.9,
                period: 1.0
            )
            .allowsHitTesting(false)
    }

    // MARK: Centered title — slides in from the right

    @ViewBuilder
    private var centerLabel: some View {
        HStack(spacing: 6) {
            Text("Approval")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(brand)
                .tracking(0.4)
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 10)
        .opacity(slid ? 1 : 0)
        .offset(x: slid ? 0 : 16)
        .allowsHitTesting(false)
    }

    // MARK: Right wing — pulsing accent dot

    private var rightSymbol: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Circle()
                .fill(brand)
                .frame(width: contentHeight * 0.42, height: contentHeight * 0.42)
                .scaleEffect(pulse ? 1.15 : 0.85)
                .opacity(pulse ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                .shadow(color: brand.opacity(0.55), radius: 4, y: 1)
                .padding(.trailing, 8)
        }
        .allowsHitTesting(false)
    }
}
