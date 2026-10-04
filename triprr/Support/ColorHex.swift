//
//  ColorHex.swift
//  triprr
//
//  Hex-string <-> SwiftUI Color bridging for trip cover colours.
//

import SwiftUI

extension Color {
    /// Creates a colour from a "#RRGGBB" (or "RRGGBB") hex string. Returns nil
    /// if the string isn't a valid 6-digit hex.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// A curated palette of cover colours offered in the trip editor.
    static let tripCoverPalette: [String] = [
        "#E4572E", // warm red
        "#F3A712", // amber
        "#4A90D9", // blue
        "#2A9D8F", // teal
        "#7B4FA3", // purple
        "#E07A9B", // pink
        "#546A7B", // slate
        "#3D8B37", // green
    ]
}
