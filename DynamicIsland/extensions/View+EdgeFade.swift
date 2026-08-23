/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import SwiftUI

/// Scroll-edge fades implemented as transparency masks.
///
/// The upstream widgets simulated edge fades by painting opaque black
/// gradients ON TOP of the content. That only works on a pure-black
/// surface — over the liquid-glass notch background those overlays render
/// as ugly dark bands. Masking fades the content itself to transparent,
/// which integrates with any background.
extension View {
    /// Fades the content to transparent over `height` points at the top
    /// and bottom edges.
    func fadedVerticalEdges(height: CGFloat = 16) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
            }
        )
    }

    /// Fades the content to transparent over `width` points at the leading
    /// and trailing edges.
    func fadedHorizontalEdges(width: CGFloat = 20) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
            }
        )
    }
}
