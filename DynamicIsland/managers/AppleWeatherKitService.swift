/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import CoreLocation
import Foundation
import WeatherKit

/// Normalized result of a WeatherKit fetch, shaped so both the notch Weather
/// tab (`NotchWeatherManager`) and the lock-screen widget
/// (`LockScreenWeatherManager`) can adapt it without importing WeatherKit
/// themselves. Temperatures and wind are already converted to the user's
/// chosen unit; symbols reuse `OpenMeteoSymbolMapper` so the look matches the
/// other providers.
struct AppleWeatherKitForecast: Sendable {
    struct Current: Sendable {
        let temperature: Double          // in user-selected unit
        let apparentTemperature: Double  // "feels like"
        let weatherCode: Int             // WMO-equivalent (for tint logic)
        let isDaytime: Bool
        let windSpeed: Double            // km/h or mph matching temperature unit
        let humidity: Int                // percent
        let symbolName: String           // pre-resolved (day/night)
        let conditionText: String
    }

    struct Hour: Sendable {
        let date: Date
        let temperature: Double
        let weatherCode: Int
        let isDaytime: Bool
        let symbolName: String
    }

    struct Day: Sendable {
        let date: Date
        let weatherCode: Int
        let symbolName: String           // daytime variant
        let minTemp: Double
        let maxTemp: Double
        let sunrise: Date?
        let sunset: Date?
    }

    let current: Current
    let hourly: [Hour]
    let daily: [Day]
    /// WeatherKit's Terms of Service require visible attribution
    /// ("Weather" + a legal link). Surfaced for the UI to display.
    let attributionName: String
}

/// Thin wrapper around Apple's native `WeatherService`. Authentication is
/// handled entirely by the embedded provisioning profile + the
/// `com.apple.developer.weatherkit` entitlement — there is no API key or
/// secret in this repo, which is why the native framework was chosen over the
/// REST API for an open-source build.
///
/// When the entitlement/profile is missing (e.g. an unsigned local dev build)
/// `WeatherService` throws; callers fall back to Open-Meteo.
enum AppleWeatherKitService {
    static func fetch(
        latitude: Double,
        longitude: Double,
        unit: LockScreenWeatherTemperatureUnit
    ) async throws -> AppleWeatherKitForecast {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather = try await WeatherService.shared.weather(for: location)

        let usesMetric = unit.usesMetricSystem
        let tempUnit: UnitTemperature = usesMetric ? .celsius : .fahrenheit
        let windUnit: UnitSpeed = usesMetric ? .kilometersPerHour : .milesPerHour

        // MARK: Current
        let cur = weather.currentWeather
        let curCode = wmoCode(for: cur.condition)
        let curSymbol = symbolAdjustedForDaylight(
            OpenMeteoSymbolMapper.mapping(for: curCode).symbol,
            isDaytime: cur.isDaylight
        )
        let current = AppleWeatherKitForecast.Current(
            temperature: cur.temperature.converted(to: tempUnit).value,
            apparentTemperature: cur.apparentTemperature.converted(to: tempUnit).value,
            weatherCode: curCode,
            isDaytime: cur.isDaylight,
            windSpeed: cur.wind.speed.converted(to: windUnit).value,
            humidity: Int((cur.humidity * 100).rounded()),
            symbolName: curSymbol,
            conditionText: cur.condition.description
        )

        // MARK: Hourly — 12 entries from the current hour forward.
        let now = Date()
        var hourly: [AppleWeatherKitForecast.Hour] = []
        for hour in weather.hourlyForecast.forecast {
            guard hour.date >= now.addingTimeInterval(-1800) else { continue }
            let code = wmoCode(for: hour.condition)
            let symbol = symbolAdjustedForDaylight(
                OpenMeteoSymbolMapper.mapping(for: code).symbol,
                isDaytime: hour.isDaylight
            )
            hourly.append(.init(
                date: hour.date,
                temperature: hour.temperature.converted(to: tempUnit).value,
                weatherCode: code,
                isDaytime: hour.isDaylight,
                symbolName: symbol
            ))
            if hourly.count == 12 { break }
        }

        // MARK: Daily — first 7 entries.
        var daily: [AppleWeatherKitForecast.Day] = []
        for day in weather.dailyForecast.forecast.prefix(7) {
            let code = wmoCode(for: day.condition)
            daily.append(.init(
                date: day.date,
                weatherCode: code,
                symbolName: OpenMeteoSymbolMapper.mapping(for: code).symbol,
                minTemp: day.lowTemperature.converted(to: tempUnit).value,
                maxTemp: day.highTemperature.converted(to: tempUnit).value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            ))
        }

        return AppleWeatherKitForecast(
            current: current,
            hourly: hourly,
            daily: daily,
            attributionName: "Weather"
        )
    }

    // MARK: WeatherCondition → WMO code

    /// Maps WeatherKit's rich `WeatherCondition` set down to the WMO codes the
    /// rest of Isle already understands. This lets WeatherKit reuse
    /// `OpenMeteoSymbolMapper` (so icons look identical across providers) and
    /// the condition-tint logic in `NotchWeatherView`.
    static func wmoCode(for condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot:
            return 0
        case .mostlyClear:
            return 1
        case .partlyCloudy, .breezy, .windy:
            return 2
        case .cloudy, .mostlyCloudy:
            return 3
        case .foggy:
            return 45
        case .haze, .smoky, .blowingDust:
            return 48
        case .drizzle:
            return 51
        case .freezingDrizzle:
            return 56
        case .rain, .sunShowers:
            return 63
        case .heavyRain:
            return 65
        case .freezingRain:
            return 66
        case .sleet, .wintryMix, .hail:
            return 67
        case .flurries, .snow, .sunFlurries, .blowingSnow, .frigid:
            return 73
        case .heavySnow, .blizzard:
            return 75
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms:
            return 95
        case .strongStorms, .hurricane, .tropicalStorm:
            return 96
        default:
            return 3
        }
    }
}
