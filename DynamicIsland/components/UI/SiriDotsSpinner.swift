/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import SwiftUI

/// Indeterminate spinner in the style of Siri's "Searching" indicator on
/// iOS/macOS 27: a ring of glowing dots whose size and brightness trail
/// off behind a rotating head, with a soft bloom around each dot.
///
/// Drop-in replacement for the stock `ProgressView()` wherever the notch
/// needs an indeterminate loading state.
struct SiriDotsSpinner: View {
    var color: Color = .white
    /// Overall diameter, in points.
    var size: CGFloat = 16
    var dotCount: Int = 8
    /// Seconds per revolution.
    var period: Double = 1.1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = (context.date.timeIntervalSinceReferenceDate / period)
                .truncatingRemainder(dividingBy: 1.0)
            ZStack {
                ForEach(0..<dotCount, id: \.self) { index in
                    dot(at: index, phase: phase)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(Text("Loading"))
    }

    @ViewBuilder
    private func dot(at index: Int, phase: Double) -> some View {
        let slot = Double(index) / Double(dotCount)
        // How far behind the rotating head this dot sits: 0 = the bright
        // head, approaching 1 = the faded end of the tail.
        let lag = (phase - slot).truncatingRemainder(dividingBy: 1.0)
        let trail = lag < 0 ? lag + 1.0 : lag
        let brightness = 1.0 - trail

        let maxDiameter = size * 0.26
        let diameter = maxDiameter * (0.35 + 0.65 * brightness)
        let orbit = (size - maxDiameter) / 2

        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(0.85 * brightness), radius: diameter * 0.55)
            .opacity(0.2 + 0.8 * brightness)
            .offset(y: -orbit)
            .rotationEffect(.degrees(slot * 360))
    }
}

#Preview("SiriDotsSpinner") {
    HStack(spacing: 24) {
        SiriDotsSpinner()
        SiriDotsSpinner(size: 28)
        SiriDotsSpinner(color: .orange, size: 22)
    }
    .padding(32)
    .background(.black)
}
