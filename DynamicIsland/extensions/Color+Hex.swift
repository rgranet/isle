/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import SwiftUI

extension Color {
    /// Initializes from a 6-digit hex string (`"#d97742"` or `"d97742"`).
    /// Falls back to `.gray` on malformed input rather than throwing.
    init(isleHex hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let rgb = UInt32(sanitized, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
