/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import SwiftUI

/// Frosted dark glass for the open notch: a behind-window blur
/// (`NSVisualEffectView`, `.hudWindow`) forced to dark vibrancy so the
/// panel always reads as smoked glass regardless of the wallpaper or the
/// system appearance.
///
/// The private `NSGlassEffectView` route (`LiquidGlassBackground`) does not
/// blur inside the borderless notch window — its backdrop renders as raw
/// transparency — so the notch uses this reliable material instead.
///
/// Shaping happens through `maskImage` (a stretched rounded rect), because
/// behind-window blurs ignore superlayer masks; callers should still keep
/// their SwiftUI `.clipShape` for the content above. The view never
/// participates in AppKit hit testing, so notch hover/click detection
/// keeps working.
struct NotchGlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    }

    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = 2.0 * cornerRadius + 1.0
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    private final class PassthroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
