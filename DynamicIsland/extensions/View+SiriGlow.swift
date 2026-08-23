/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import SwiftUI

/// Siri-style breathing glow: a blurred, tinted halo of `shape` rendered
/// behind the view, pulsing between two opacities while active.
///
/// Factors the recipe previously copy-pasted across the live activities
/// (blurred brand-color fill + `repeatForever` opacity pulse). The halo
/// never intercepts hit testing, so it is safe inside closed-notch live
/// activities where hover-open detection must keep receiving events.
struct SiriGlowModifier<GlowShape: Shape>: ViewModifier {
    let color: Color
    let shape: GlowShape
    /// Extra points the halo extends past the content on every side.
    let spread: CGFloat
    let blurRadius: CGFloat
    /// Opacity oscillates between `lowerBound` (dim) and `upperBound` (peak).
    let opacityRange: ClosedRange<Double>
    /// Seconds for one dim → peak leg of the breath.
    let period: Double
    let isActive: Bool

    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(color)
                    .padding(-spread)
                    .blur(radius: blurRadius)
                    .opacity(isActive ? (pulse ? opacityRange.upperBound : opacityRange.lowerBound) : 0)
                    .animation(.easeInOut(duration: 0.25), value: isActive)
                    .allowsHitTesting(false)
            }
            .onAppear {
                if isActive { startPulsing() }
            }
            .onChange(of: isActive) { _, nowActive in
                if nowActive { startPulsing() } else { stopPulsing() }
            }
    }

    private func startPulsing() {
        pulse = false
        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func stopPulsing() {
        withAnimation(.easeInOut(duration: 0.25)) {
            pulse = false
        }
    }
}

extension View {
    /// Breathing halo shaped like `shape` behind the view (badges, cards).
    func siriGlow<GlowShape: Shape>(
        _ color: Color,
        in shape: GlowShape,
        spread: CGFloat = 2,
        blurRadius: CGFloat = 4,
        opacityRange: ClosedRange<Double> = 0.45...0.85,
        period: Double = 1.1,
        isActive: Bool = true
    ) -> some View {
        modifier(SiriGlowModifier(
            color: color,
            shape: shape,
            spread: spread,
            blurRadius: blurRadius,
            opacityRange: opacityRange,
            period: period,
            isActive: isActive
        ))
    }

    /// Circular breathing halo behind the view (dots, symbols).
    func siriGlow(
        _ color: Color,
        spread: CGFloat = 2,
        blurRadius: CGFloat = 4,
        opacityRange: ClosedRange<Double> = 0.45...0.85,
        period: Double = 1.1,
        isActive: Bool = true
    ) -> some View {
        siriGlow(
            color,
            in: Circle(),
            spread: spread,
            blurRadius: blurRadius,
            opacityRange: opacityRange,
            period: period,
            isActive: isActive
        )
    }
}
