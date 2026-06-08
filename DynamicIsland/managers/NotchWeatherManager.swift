/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Combine
import CoreLocation
import Defaults
import Foundation

// MARK: - Data models

struct NotchCurrentWeather: Equatable {
    let temperature: Double            // in user-selected unit
    let apparentTemperature: Double?   // "feels like"
    let weatherCode: Int               // WMO code
    let isDaytime: Bool
    let windSpeed: Double              // km/h or mph matching temperature unit
    let humidity: Int                  // percent
    let symbolName: String             // pre-resolved (day/night)
    let conditionText: String
}

struct NotchHourlyForecast: Identifiable, Equatable {
    let id: Date  // the hour
    let temperature: Double
    let weatherCode: Int
    let isDaytime: Bool
    let symbolName: String
}

struct NotchDailyForecast: Identifiable, Equatable {
    let id: Date  // local midnight of the day
    let weatherCode: Int
    let symbolName: String
    let minTemp: Double
    let maxTemp: Double
}

enum NotchWeatherLoadState: Equatable {
    case idle
    case loading
    case ready
    case locationDenied
    case error(String)
}

// MARK: - Manager

@MainActor
final class NotchWeatherManager: ObservableObject {
    static let shared = NotchWeatherManager()

    @Published private(set) var current: NotchCurrentWeather?
    @Published private(set) var hourly: [NotchHourlyForecast] = []
    @Published private(set) var daily: [NotchDailyForecast] = []
    @Published private(set) var placeName: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var state: NotchWeatherLoadState = .idle

    private let locationProvider: WeatherLocationProvider
    private let session: URLSession
    private let geocoder = CLGeocoder()
    private var inflightFetch: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Free-tier Open-Meteo doesn't need a key but politeness suggests we
    /// don't hammer it. 15-minute freshness gate matches the spec.
    private let stalenessThreshold: TimeInterval = 15 * 60

    init(locationProvider: WeatherLocationProvider? = nil) {
        self.locationProvider = locationProvider ?? WeatherLocationProvider()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)

        // Refresh immediately when the user flips the temperature unit so
        // numbers don't lag behind the toggle.
        Defaults.publisher(.lockScreenWeatherTemperatureUnit)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshNow()
            }
            .store(in: &cancellables)

        self.locationProvider.prepareAuthorization()
    }

    // MARK: Public API

    /// Refresh only if data is stale (> 15 min) or absent.
    func refreshIfStale() {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < stalenessThreshold {
            return
        }
        refreshNow()
    }

    /// Force a refresh regardless of freshness.
    func refreshNow() {
        inflightFetch?.cancel()
        inflightFetch = Task { [weak self] in
            await self?.performFetch()
        }
    }

    // MARK: Fetch pipeline

    private func performFetch() async {
        state = .loading

        guard let location = await locationProvider.currentLocation() else {
            let auth = locationProvider.authorizationStatus
            if auth == .denied || auth == .restricted {
                state = .locationDenied
            } else {
                state = .error("Unable to determine your location.")
            }
            return
        }

        do {
            // Apple Weather (WeatherKit) is the default. When it's selected we
            // try it first and silently fall back to Open-Meteo if the
            // entitlement/provisioning profile is unavailable (e.g. an unsigned
            // local dev build) or the service errors.
            if Defaults[.lockScreenWeatherProviderSource] == .appleWeatherKit,
               await applyAppleWeatherKit(location: location) {
                await updatePlaceName(for: location)
                lastRefresh = .now
                state = .ready
                return
            }

            let payload = try await fetchOpenMeteo(location: location)
            applyPayload(payload)
            await updatePlaceName(for: location)
            lastRefresh = .now
            state = .ready
        } catch is CancellationError {
            // A fresher request superseded us; leave state as the new request set it.
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fetches via WeatherKit and applies the result. Returns `false` (without
    /// mutating published state) if the service is unavailable, so the caller
    /// can fall back to Open-Meteo.
    private func applyAppleWeatherKit(location: CLLocation) async -> Bool {
        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        do {
            let forecast = try await AppleWeatherKitService.fetch(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                unit: unit
            )
            current = NotchCurrentWeather(
                temperature: forecast.current.temperature,
                apparentTemperature: forecast.current.apparentTemperature,
                weatherCode: forecast.current.weatherCode,
                isDaytime: forecast.current.isDaytime,
                windSpeed: forecast.current.windSpeed,
                humidity: forecast.current.humidity,
                symbolName: forecast.current.symbolName,
                conditionText: forecast.current.conditionText
            )
            hourly = forecast.hourly.map {
                NotchHourlyForecast(
                    id: $0.date,
                    temperature: $0.temperature,
                    weatherCode: $0.weatherCode,
                    isDaytime: $0.isDaytime,
                    symbolName: $0.symbolName
                )
            }
            daily = forecast.daily.map {
                NotchDailyForecast(
                    id: $0.date,
                    weatherCode: $0.weatherCode,
                    symbolName: $0.symbolName,
                    minTemp: $0.minTemp,
                    maxTemp: $0.maxTemp
                )
            }
            return true
        } catch {
            return false
        }
    }

    private func applyPayload(_ payload: OpenMeteoForecastResponse) {
        // Current
        if let cur = payload.current {
            let isDay = (cur.isDay ?? 1) == 1
            let mapping = OpenMeteoSymbolMapper.mapping(for: cur.weatherCode ?? 0)
            let symbol = symbolAdjustedForDaylight(mapping.symbol, isDaytime: isDay)
            current = NotchCurrentWeather(
                temperature: cur.temperature2M ?? 0,
                apparentTemperature: cur.apparentTemperature,
                weatherCode: cur.weatherCode ?? 0,
                isDaytime: isDay,
                windSpeed: cur.windSpeed10M ?? 0,
                humidity: Int(cur.relativeHumidity2M ?? 0),
                symbolName: symbol,
                conditionText: mapping.description
            )
        }

        // Hourly — keep the 12 entries starting from the current hour.
        let now = Date()
        var hourlyOut: [NotchHourlyForecast] = []
        if let h = payload.hourly,
           let times = h.time,
           let temps = h.temperature2M,
           let codes = h.weatherCode,
           let days = h.isDay {
            let count = min(times.count, temps.count, codes.count, days.count)
            for i in 0..<count {
                guard let date = parseISODate(times[i], timezoneIdentifier: payload.timezone, offsetSeconds: payload.utcOffsetSeconds) else { continue }
                guard date >= now.addingTimeInterval(-1800) else { continue } // skip past hours (with 30-min grace)
                let isDay = days[i] == 1
                let baseSymbol = OpenMeteoSymbolMapper.mapping(for: codes[i]).symbol
                let symbol = symbolAdjustedForDaylight(baseSymbol, isDaytime: isDay)
                hourlyOut.append(NotchHourlyForecast(
                    id: date,
                    temperature: temps[i],
                    weatherCode: codes[i],
                    isDaytime: isDay,
                    symbolName: symbol
                ))
                if hourlyOut.count == 12 { break }
            }
        }
        hourly = hourlyOut

        // Daily — first 7 entries.
        var dailyOut: [NotchDailyForecast] = []
        if let d = payload.daily,
           let times = d.time,
           let maxes = d.temperature2MMax,
           let mins = d.temperature2MMin,
           let codes = d.weatherCode {
            let count = min(times.count, maxes.count, mins.count, codes.count, 7)
            for i in 0..<count {
                guard let date = parseISODate(times[i], timezoneIdentifier: payload.timezone, offsetSeconds: payload.utcOffsetSeconds) else { continue }
                let baseSymbol = OpenMeteoSymbolMapper.mapping(for: codes[i]).symbol
                dailyOut.append(NotchDailyForecast(
                    id: date,
                    weatherCode: codes[i],
                    symbolName: baseSymbol,  // daily icons always daytime
                    minTemp: mins[i],
                    maxTemp: maxes[i]
                ))
            }
        }
        daily = dailyOut
    }

    private func updatePlaceName(for location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            placeName = placemarks.first?.locality
                ?? placemarks.first?.subAdministrativeArea
                ?? placemarks.first?.administrativeArea
        } catch {
            placeName = nil  // city slot stays empty; rest of UI keeps working
        }
    }

    // MARK: Open-Meteo HTTP

    private func fetchOpenMeteo(location: CLLocation) async throws -> OpenMeteoForecastResponse {
        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        if let tempParam = unit.openMeteoTemperatureParameter {
            items.append(URLQueryItem(name: "temperature_unit", value: tempParam))
        }
        // Wind unit follows temperature unit choice.
        items.append(URLQueryItem(name: "wind_speed_unit", value: unit.usesMetricSystem ? "kmh" : "mph"))
        components.queryItems = items
        guard let url = components.url else {
            throw NotchWeatherError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotchWeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenMeteoForecastResponse.self, from: data)
    }

    private func parseISODate(_ value: String, timezoneIdentifier: String?, offsetSeconds: Int?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let id = timezoneIdentifier, let tz = TimeZone(identifier: id) {
            formatter.timeZone = tz
        } else if let offset = offsetSeconds, let tz = TimeZone(secondsFromGMT: offset) {
            formatter.timeZone = tz
        }
        if let date = formatter.date(from: value) { return date }
        // Daily entries are date-only ("yyyy-MM-dd"), retry.
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

enum NotchWeatherError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Couldn't build the weather URL."
        case .invalidResponse: return "The weather service returned an unexpected response."
        }
    }
}

// MARK: - Open-Meteo response decoder

private struct OpenMeteoForecastResponse: Decodable {
    let timezone: String?
    let utcOffsetSeconds: Int?
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable {
        let temperature2M: Double?
        let apparentTemperature: Double?
        let weatherCode: Int?
        let isDay: Int?
        let windSpeed10M: Double?
        let relativeHumidity2M: Double?
    }

    struct Hourly: Decodable {
        let time: [String]?
        let temperature2M: [Double]?
        let weatherCode: [Int]?
        let isDay: [Int]?
    }

    struct Daily: Decodable {
        let time: [String]?
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
        let weatherCode: [Int]?
        let sunrise: [String]?
        let sunset: [String]?
    }
}
