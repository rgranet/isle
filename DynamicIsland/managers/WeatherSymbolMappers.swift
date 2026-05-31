/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Foundation

/// Maps Open-Meteo WMO weather codes to SF Symbol names and human-readable
/// descriptions. Used by both the lock-screen widget and the notch Weather
/// tab. Returned `symbol` is the daytime variant — call
/// `symbolAdjustedForDaylight(_:isDaytime:)` to swap to the night version.
enum OpenMeteoSymbolMapper {
    static func mapping(for code: Int) -> (symbol: String, description: String) {
        switch code {
        case 0:
            return ("sun.max.fill", "Clear sky")
        case 1:
            return ("cloud.sun.fill", "Mainly clear")
        case 2:
            return ("cloud.sun.fill", "Partly cloudy")
        case 3:
            return ("cloud.fill", "Overcast")
        case 45, 48:
            return ("cloud.fog.fill", "Fog")
        case 51, 53, 55:
            return ("cloud.drizzle.fill", "Drizzle")
        case 56, 57:
            return ("cloud.sleet.fill", "Freezing drizzle")
        case 61, 63, 65:
            return ("cloud.rain.fill", "Rain")
        case 66, 67:
            return ("cloud.sleet.fill", "Freezing rain")
        case 71, 73, 75, 77:
            return ("cloud.snow.fill", "Snow")
        case 80, 81, 82:
            return ("cloud.heavyrain.fill", "Rain showers")
        case 85, 86:
            return ("cloud.snow.fill", "Snow showers")
        case 95:
            return ("cloud.bolt.rain.fill", "Thunderstorm")
        case 96, 99:
            return ("cloud.bolt.rain.fill", "Thunderstorm with hail")
        default:
            return ("cloud.sun.fill", "Cloudy")
        }
    }
}

/// Maps wttr.in weather codes to SF Symbol names. Kept for parity with the
/// lock-screen widget's wttr.in provider path.
enum WeatherSymbolMapper {
    static func symbol(for code: Int) -> String {
        switch code {
        case 113:
            return "sun.max.fill"
        case 116:
            return "cloud.sun.fill"
        case 119, 122:
            return "cloud.fill"
        case 143, 248, 260:
            return "cloud.fog.fill"
        case 176, 263, 266, 293, 296, 299, 302, 353, 356, 359:
            return "cloud.rain.fill"
        case 179, 182, 185, 311, 314, 317, 320, 362, 365:
            return "cloud.sleet.fill"
        case 227, 230, 281, 284, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377:
            return "cloud.snow.fill"
        case 200, 386, 389, 392, 395:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.sun.fill"
        }
    }
}

/// Swaps daytime symbols for their night variants when `isDaytime == false`.
/// Symbols that look the same day/night are returned unchanged.
func symbolAdjustedForDaylight(_ symbol: String, isDaytime: Bool) -> String {
    guard !isDaytime else { return symbol }
    switch symbol {
    case "sun.max.fill":
        return "moon.stars.fill"
    case "cloud.sun.fill":
        return "cloud.moon.fill"
    case "cloud.sun.rain.fill":
        return "cloud.moon.rain.fill"
    case "cloud.sun.bolt.fill":
        return "cloud.moon.bolt.fill"
    default:
        return symbol
    }
}
