/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import SwiftUI

/// Closed-notch "grow on arrival" bandeau shown for ~3 seconds when a
/// new unread message lands. After the auto-hide expires the notch
/// collapses back to the compact `MessagingLiveActivity`.
struct MessagingArrivedExpandedView: View {
    let appID: String
    let count: Int

    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var slid = false

    private var app: MessagingApp? {
        MessagingApp.allCases.first { $0.rawValue == appID }
    }

    private var brand: Color {
        app.map { Color(isleHex: $0.brandColorHex) } ?? .gray
    }

    private var contentHeight: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }
    private var wingWidth: CGFloat { contentHeight }
    private var centerWidth: CGFloat { max(vm.closedNotchSize.width, 120) }

    var body: some View {
        HStack(spacing: 0) {
            leftIcon
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

            rightCount
                .frame(width: wingWidth + 16, height: contentHeight)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { slid = true }
        }
    }

    // MARK: Left — app icon (asset if shipped, fallback brand square)

    @ViewBuilder
    private var leftIcon: some View {
        let badge = contentHeight * 0.82
        ZStack {
            if let app, NSImage(named: app.iconAssetName) != nil {
                Image(app.iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badge, height: badge)
                    .clipShape(RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous))
                    .shadow(color: brand.opacity(0.5), radius: 4, y: 2)
            } else if let app {
                RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous)
                    .fill(brand)
                    .frame(width: badge, height: badge)
                    .overlay(
                        Image(systemName: app.fallbackSymbol)
                            .font(.system(size: badge * 0.5, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: brand.opacity(0.5), radius: 4, y: 2)
            }
        }
        .siriGlow(
            brand,
            in: RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous),
            blurRadius: 5,
            period: 1.2
        )
        .allowsHitTesting(false)
    }

    // MARK: Center — app name + "new message"

    @ViewBuilder
    private var centerLabel: some View {
        HStack(spacing: 6) {
            Text(app?.displayName.uppercased() ?? "MESSAGE")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(brand)
                .tracking(0.4)
            Text(count == 1 ? "1 new message" : "\(count) new messages")
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

    // MARK: Right — chunky count capsule

    private var rightCount: some View {
        let label = count > 99 ? "99+" : "\(count)"
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(brand)
                .overlay(
                    Text(label)
                        .font(.system(size: contentHeight * 0.38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                )
                .frame(height: contentHeight * 0.6)
                .fixedSize()
                .shadow(color: brand.opacity(0.55), radius: 4, y: 1)
                .padding(.trailing, 8)
        }
        .allowsHitTesting(false)
    }
}
