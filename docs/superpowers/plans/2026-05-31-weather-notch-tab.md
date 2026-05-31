# Weather Notch Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Weather` tab to the open notch (alongside Home/Shelf/Agents) showing current conditions, a 12-hour scroll strip, and a 7-day forecast. Reuse the existing Open-Meteo + wttr.in infrastructure already powering the lock-screen weather widget.

**Architecture:** Lift four shared utilities out of `LockScreenWeatherManager.swift` (location provider, two symbol mappers, daylight switcher) into new internal-visibility files so a new `NotchWeatherManager` can call them. Build a SwiftUI `NotchWeatherView` with three sections (hero / hourly / daily) and wire it through `NotchViews.weather`, ContentView's tab dispatcher, the tab nav header, and a new Settings pane.

**Tech Stack:** Swift 5, SwiftUI, macOS 14+, `Defaults` library, `CoreLocation`, `URLSession`, Open-Meteo HTTP API. **No new dependencies, no new Apple entitlements, no Developer Portal changes.**

**Spec:** [`docs/superpowers/specs/2026-05-31-weather-notch-tab-design.md`](../specs/2026-05-31-weather-notch-tab-design.md)

**Testing note:** This codebase has no XCTest target visible. Verification at each task is `xcodebuild` clean + manual smoke test (run the app, click Weather tab, verify behavior). Commit after each task.

**GPL header for every new `.swift` file:**

```swift
/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */
```

**Build command (used in many tasks):**

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -40
```

Expected: ends with `** BUILD SUCCEEDED **`. If failure: read errors, fix, rebuild.

---

## File Structure

**New files (5):**

| Path | Responsibility |
|---|---|
| `DynamicIsland/managers/WeatherLocationProvider.swift` | Shared `CLLocationManager` wrapper (extracted from LockScreen). Async/await API. Cache 30 min. Used by both lock-screen and notch tab. |
| `DynamicIsland/managers/WeatherSymbolMappers.swift` | Shared `OpenMeteoSymbolMapper`, `WeatherSymbolMapper` (wttr.in), and `symbolAdjustedForDaylight` function. |
| `DynamicIsland/managers/NotchWeatherManager.swift` | New `@MainActor` singleton. Fetches Open-Meteo current+hourly+daily, exposes `@Published` data, reverse-geocodes city, freshness-gated refresh. |
| `DynamicIsland/components/Notch/NotchWeatherView.swift` | The tab UI. Hero + hourly scroll + daily list + non-nominal states. |
| `DynamicIsland/components/Settings/WeatherSettings.swift` | Settings pane: master toggle, units (shared key with lock-screen), refresh button, permission diagnostic. |

**Modified files (5):**

| Path | What changes |
|---|---|
| `DynamicIsland/managers/LockScreenWeatherManager.swift` | Remove the now-extracted `private final class LockScreenWeatherLocationProvider`, `private enum OpenMeteoSymbolMapper`, `private enum WeatherSymbolMapper`, `private func symbolAdjustedForDaylight`. Update call sites to use the new shared types. |
| `DynamicIsland/enums/generic.swift` | Add `case weather` to `NotchViews` enum. |
| `DynamicIsland/models/Constants.swift` | Add `enableNotchWeather` Defaults key. |
| `DynamicIsland/ContentView.swift` | Add `case .weather: NotchWeatherView()` branch to the tab dispatcher switch at line ~1120. |
| `DynamicIsland/components/Settings/SettingsView.swift` | Add `case weather` to `SettingsTab` enum (id, group, title, icon, tint, content route to `WeatherSettings()`). |

**Probably modified (1)** — depends on what the implementor finds:

| Path | What changes |
|---|---|
| Wherever the open-notch tab buttons live (likely `DynamicIslandHeader.swift` or a `NotchTabsView` — Task 9 finds it) | Add a "Weather" tab button gated on `Defaults[.enableNotchWeather]`. |

---

## Task 1: Extract `WeatherLocationProvider` into its own file

**Files:**
- Create: `DynamicIsland/managers/WeatherLocationProvider.swift`
- Modify: `DynamicIsland/managers/LockScreenWeatherManager.swift:1091-1142` (remove private class), and the `private let locationProvider = LockScreenWeatherLocationProvider()` at line 31 (rename type).

- [ ] **Step 1: Read current source to preserve behavior**

Run:
```sh
sed -n '1091,1142p' DynamicIsland/managers/LockScreenWeatherManager.swift
```
Confirm this prints the `private final class LockScreenWeatherLocationProvider: NSObject, CLLocationManagerDelegate { … }` block.

- [ ] **Step 2: Create the new shared file**

Create `DynamicIsland/managers/WeatherLocationProvider.swift` with this exact content:

```swift
/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import CoreLocation
import Foundation

/// Shared `CLLocationManager` wrapper used by both the lock-screen weather
/// widget and the notch Weather tab. Async/await API, in-memory cache of the
/// last fix (valid for 30 minutes), no background updates.
@MainActor
final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var pendingContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var lastLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Triggers the macOS "this app would like to use your location" prompt
    /// the first time. Safe to call repeatedly — it's a no-op once status is
    /// determined.
    func prepareAuthorization() {
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Returns the user's current location, or `nil` if permission is missing
    /// or the system can't produce a fix. Cached for 30 minutes between calls.
    func currentLocation() async -> CLLocation? {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 1800 {
                return lastLocation
            }
            manager.requestLocation()
            return await withCheckedContinuation { continuation in
                self.pendingContinuations.append(continuation)
            }
        default:
            return nil
        }
    }

    /// Current authorization status, exposed so UIs can show "denied" states.
    var authorizationStatus: CLAuthorizationStatus {
        CLLocationManager.authorizationStatus()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.lastLocation = locations.last
            self?.flushContinuations(with: locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.flushContinuations(with: nil)
        }
    }

    private func flushContinuations(with location: CLLocation?) {
        guard !pendingContinuations.isEmpty else { return }
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: location) }
    }
}
```

- [ ] **Step 3: Remove the private class from `LockScreenWeatherManager.swift`**

Open `DynamicIsland/managers/LockScreenWeatherManager.swift`. Delete lines 1091 through 1142 (the entire `@MainActor private final class LockScreenWeatherLocationProvider: NSObject, CLLocationManagerDelegate { … }` block, including the closing brace).

- [ ] **Step 4: Rename the stored property type in `LockScreenWeatherManager.swift`**

In `LockScreenWeatherManager.swift`, find line 31:
```swift
    private let locationProvider = LockScreenWeatherLocationProvider()
```

Replace with:
```swift
    private let locationProvider = WeatherLocationProvider()
```

- [ ] **Step 5: Build to verify the refactor is clean**

Run:
```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -40
```
Expected: `** BUILD SUCCEEDED **`. If failure: most likely a missed reference to `LockScreenWeatherLocationProvider`. Search with `grep -rn LockScreenWeatherLocationProvider DynamicIsland/` and replace any hits with `WeatherLocationProvider`.

- [ ] **Step 6: Smoke test the lock-screen widget still works**

Launch the app via Xcode (Cmd-R). Lock the screen (Ctrl-Cmd-Q). The weather widget on the lock screen should still show temperature + symbol. Unlock and confirm.

- [ ] **Step 7: Commit**

```sh
git add DynamicIsland/managers/WeatherLocationProvider.swift DynamicIsland/managers/LockScreenWeatherManager.swift
git commit -m "refactor: extract WeatherLocationProvider for reuse by notch tab"
```

---

## Task 2: Extract weather symbol mappers and daylight helper

**Files:**
- Create: `DynamicIsland/managers/WeatherSymbolMappers.swift`
- Modify: `DynamicIsland/managers/LockScreenWeatherManager.swift:1013-1089` (remove three private types)

- [ ] **Step 1: Create the new shared file**

Create `DynamicIsland/managers/WeatherSymbolMappers.swift` with this exact content:

```swift
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
```

- [ ] **Step 2: Remove the three private definitions from `LockScreenWeatherManager.swift`**

In `DynamicIsland/managers/LockScreenWeatherManager.swift`, delete:
- The `private enum OpenMeteoSymbolMapper { … }` block at lines ~1013-1048
- The `private enum WeatherSymbolMapper { … }` block at lines ~1050-1073
- The `private func symbolAdjustedForDaylight(_ symbol: String, isDaytime: Bool) -> String { … }` function at lines ~1075-1089

After deletion, the file ends cleanly. The call sites inside the actor (`provider.fetchOpenMeteoSnapshot`, `provider.fetchWttrSnapshot`) already reference `OpenMeteoSymbolMapper.mapping(...)`, `WeatherSymbolMapper.symbol(...)`, and `symbolAdjustedForDaylight(...)` by their bare names — they'll resolve to the new module-internal types automatically.

- [ ] **Step 3: Build to verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If failure: a call site might be `private` to the actor and need access tweaks — check the error message for the specific line.

- [ ] **Step 4: Smoke test lock-screen widget still works**

Cmd-R, lock screen, verify the widget shows. Unlock.

- [ ] **Step 5: Commit**

```sh
git add DynamicIsland/managers/WeatherSymbolMappers.swift DynamicIsland/managers/LockScreenWeatherManager.swift
git commit -m "refactor: extract weather symbol mappers for reuse by notch tab"
```

---

## Task 3: Define the `NotchWeatherManager` data models

**Files:**
- Create: `DynamicIsland/managers/NotchWeatherManager.swift` (models only — manager itself comes in Task 4)

- [ ] **Step 1: Create the file with models only**

Create `DynamicIsland/managers/NotchWeatherManager.swift` with this exact content:

```swift
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

// Manager comes in Task 4.
```

- [ ] **Step 2: Build to verify the models compile**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Synchronized Xcode groups auto-include the new file — no pbxproj edit needed.

- [ ] **Step 3: Commit**

```sh
git add DynamicIsland/managers/NotchWeatherManager.swift
git commit -m "feat: add NotchWeatherManager data models"
```

---

## Task 4: Implement `NotchWeatherManager` (fetch + state)

**Files:**
- Modify: `DynamicIsland/managers/NotchWeatherManager.swift` (append manager class + Open-Meteo decoder)

- [ ] **Step 1: Append the manager and decoder to the file**

In `DynamicIsland/managers/NotchWeatherManager.swift`, replace the trailing `// Manager comes in Task 4.` comment with this code:

```swift
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

    init(locationProvider: WeatherLocationProvider = WeatherLocationProvider()) {
        self.locationProvider = locationProvider

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

        locationProvider.prepareAuthorization()
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
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If `Defaults.publisher(.lockScreenWeatherTemperatureUnit)` causes an "unknown key" error, the existing key may be named differently — `grep -n "lockScreenWeatherTemperatureUnit" DynamicIsland/models/Constants.swift` to confirm the exact name.

- [ ] **Step 3: Commit**

```sh
git add DynamicIsland/managers/NotchWeatherManager.swift
git commit -m "feat: implement NotchWeatherManager Open-Meteo fetch pipeline"
```

---

## Task 5: Add the `enableNotchWeather` Defaults key

**Files:**
- Modify: `DynamicIsland/models/Constants.swift` (add one key near other notch-related toggles)

- [ ] **Step 1: Find a good insertion point**

Run:
```sh
grep -n "enableCodingAgents" DynamicIsland/models/Constants.swift
```
Expected: a line like `static let enableCodingAgents = Key<Bool>("enableCodingAgents", default: true)` around line 1053. Use that as the anchor.

- [ ] **Step 2: Add the key**

Insert this line directly below `enableCodingAgents`:

```swift
    static let enableNotchWeather = Key<Bool>("enableNotchWeather", default: true)
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```sh
git add DynamicIsland/models/Constants.swift
git commit -m "feat: add enableNotchWeather Defaults key"
```

---

## Task 6: Add `.weather` case to `NotchViews` enum

**Files:**
- Modify: `DynamicIsland/enums/generic.swift:73-85`

- [ ] **Step 1: Add the case**

In `DynamicIsland/enums/generic.swift`, the `NotchViews` enum currently reads:

```swift
public enum NotchViews {
    case home
    case codingAgents
    case messages
    case shelf
    case timer
    case stats
    case colorPicker
    case notes
    case clipboard
    case terminal
    case extensionExperience
}
```

Add `case weather` as a new line directly after `case codingAgents`:

```swift
public enum NotchViews {
    case home
    case codingAgents
    case weather
    case messages
    case shelf
    case timer
    case stats
    case colorPicker
    case notes
    case clipboard
    case terminal
    case extensionExperience
}
```

- [ ] **Step 2: Build to surface non-exhaustive switch errors**

Run the build command. Expected: the build will likely FAIL with `Switch must be exhaustive` errors pointing to `ContentView.swift` around line 1120 (the tab dispatcher). That's expected — Task 7 fixes it.

- [ ] **Step 3: Commit (build broken is OK at this checkpoint — next task fixes it)**

```sh
git add DynamicIsland/enums/generic.swift
git commit -m "feat: add weather case to NotchViews enum"
```

---

## Task 7: Create the `NotchWeatherView` SwiftUI view

**Files:**
- Create: `DynamicIsland/components/Notch/NotchWeatherView.swift`

- [ ] **Step 1: Create the file with the full view**

Create `DynamicIsland/components/Notch/NotchWeatherView.swift` with this exact content:

```swift
/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Defaults
import SwiftUI

/// Open-notch Weather tab. Three sections: hero (current), hourly scroll,
/// 7-day daily list. Handles loading / location-denied / error states.
struct NotchWeatherView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var manager = NotchWeatherManager.shared
    @Default(.lockScreenWeatherTemperatureUnit) private var unit

    @State private var hoverSuppressionToken = UUID()
    @State private var refreshSpinning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            manager.refreshIfStale()
            updateSuppression(active: true)
        }
        .onDisappear {
            updateSuppression(active: false)
        }
        .onHover { hovering in
            updateSuppression(active: hovering)
        }
    }

    // MARK: Header (city + freshness + refresh)

    private var header: some View {
        HStack {
            Text(manager.placeName ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if let last = manager.lastRefresh {
                Text("Updated \(last, format: .relative(presentation: .numeric))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Button {
                refreshSpinning = true
                manager.refreshNow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { refreshSpinning = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(refreshSpinning ? 360 : 0))
                    .animation(.linear(duration: 0.6), value: refreshSpinning)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityLabel("Refresh weather")
        }
        .padding(.bottom, 2)
    }

    // MARK: Content — switches on state

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle, .loading where manager.current == nil:
            loadingPlaceholder
        case .locationDenied:
            locationDeniedPlaceholder
        case .error(let message) where manager.current == nil:
            errorPlaceholder(message: message)
        default:
            readyContent
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let current = manager.current {
                heroRow(current)
            }
            Divider().background(.white.opacity(0.15))
            if !manager.hourly.isEmpty {
                hourlyStrip
            }
            Divider().background(.white.opacity(0.15))
            if !manager.daily.isEmpty {
                dailyList
            }
        }
    }

    // MARK: Hero

    private func heroRow(_ current: NotchCurrentWeather) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: current.symbolName)
                .font(.system(size: 38, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(round(current.temperature)))°")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(current.conditionText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Text(secondaryLine(for: current))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func secondaryLine(for current: NotchCurrentWeather) -> String {
        var parts: [String] = []
        if let feels = current.apparentTemperature {
            parts.append("Feels \(Int(round(feels)))°")
        }
        let windUnit = unit.usesMetricSystem ? "km/h" : "mph"
        parts.append("Wind \(Int(round(current.windSpeed))) \(windUnit)")
        parts.append("Humidity \(current.humidity)%")
        return parts.joined(separator: " · ")
    }

    // MARK: Hourly strip

    private var hourlyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(manager.hourly) { hour in
                    VStack(spacing: 4) {
                        Text(hour.id, format: .dateTime.hour())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: hour.symbolName)
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .frame(height: 18)
                        Text("\(Int(round(hour.temperature)))°")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(minWidth: 32)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Daily list

    private var dailyList: some View {
        let range = weeklyTempRange()
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(manager.daily.enumerated()), id: \.element.id) { idx, day in
                HStack(spacing: 10) {
                    Text(dayLabel(for: day.id, index: idx))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .font(.system(size: 13))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 18)
                    Text("\(Int(round(day.minTemp)))°")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 26, alignment: .trailing)
                    rangeBar(min: day.minTemp, max: day.maxTemp, weekRange: range)
                        .frame(height: 4)
                    Text("\(Int(round(day.maxTemp)))°")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, alignment: .leading)
                }
            }
        }
    }

    private func rangeBar(min dayMin: Double, max dayMax: Double, weekRange: ClosedRange<Double>) -> some View {
        GeometryReader { proxy in
            let span = weekRange.upperBound - weekRange.lowerBound
            let safeSpan = span <= 0 ? 1 : span
            let startFrac = (dayMin - weekRange.lowerBound) / safeSpan
            let endFrac = (dayMax - weekRange.lowerBound) / safeSpan
            let x = proxy.size.width * CGFloat(startFrac)
            let w = max(2, proxy.size.width * CGFloat(endFrac - startFrac))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w)
                    .offset(x: x)
            }
        }
    }

    private func weeklyTempRange() -> ClosedRange<Double> {
        let mins = manager.daily.map(\.minTemp)
        let maxes = manager.daily.map(\.maxTemp)
        guard let lo = mins.min(), let hi = maxes.max(), lo < hi else {
            return 0...1
        }
        return lo...hi
    }

    private func dayLabel(for date: Date, index: Int) -> String {
        if index == 0 { return "Today" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    // MARK: Placeholders

    private var loadingPlaceholder: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text("Fetching weather…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationDeniedPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            Text("Location access needed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorPlaceholder(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Retry") { manager.refreshNow() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hover suppression (notch gotcha)

    private func updateSuppression(active: Bool) {
        vm.setScrollGestureSuppression(active, token: hoverSuppressionToken)
        vm.setAutoCloseSuppression(active, token: hoverSuppressionToken)
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: still fails with the non-exhaustive switch error in `ContentView.swift` (left over from Task 6) — that's expected; Task 8 fixes the dispatcher.

If you see errors about `vm.setScrollGestureSuppression(_:token:)` or `vm.setAutoCloseSuppression(_:token:)` not existing, run:
```sh
grep -n "setScrollGestureSuppression\|setAutoCloseSuppression" DynamicIsland/models/DynamicIslandViewModel.swift
```
Both should exist (they're used by `NotchCodingAgentsView`). If the signatures differ slightly, adjust the calls in `updateSuppression`.

- [ ] **Step 3: Commit**

```sh
git add DynamicIsland/components/Notch/NotchWeatherView.swift
git commit -m "feat: add NotchWeatherView SwiftUI tab"
```

---

## Task 8: Wire `.weather` into ContentView's tab dispatcher

**Files:**
- Modify: `DynamicIsland/ContentView.swift:1120-1147` (the `switch coordinator.currentView` block)

- [ ] **Step 1: Add the case**

In `DynamicIsland/ContentView.swift`, find the dispatcher around line 1120:

```swift
switch coordinator.currentView {
    case .home:
        NotchHomeView(albumArtNamespace: albumArtNamespace)
    case .codingAgents:
        NotchCodingAgentsView()
    case .messages:
        NotchMessagesView()
    …
```

Add a new branch right after `.codingAgents`:

```swift
    case .weather:
        NotchWeatherView()
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. The previously non-exhaustive switch is now exhaustive.

- [ ] **Step 3: Manual smoke test the view renders**

Cmd-R. Once the app is launched, force the tab open by typing in lldb (or by adding a one-off in code), or skip to Task 9 which adds the nav button.

For now, set it programmatically: in the running app, with Xcode paused at any breakpoint, run in the lldb console:
```
e DynamicIslandViewCoordinator.shared.currentView = .weather
```
Then continue and hover the notch open. You should see the Weather tab render (loading state at first, then data once the location prompt is answered).

If the location prompt doesn't appear, check System Settings → Privacy & Security → Location Services and verify Isle is listed (it may already be authorized via the lock-screen widget).

- [ ] **Step 4: Commit**

```sh
git add DynamicIsland/ContentView.swift
git commit -m "feat: wire weather tab into ContentView dispatcher"
```

---

## Task 9: Add the "Weather" button to the notch tab nav

**Files:**
- Modify: TBD by inspection — likely `DynamicIsland/components/Notch/DynamicIslandHeader.swift` or wherever the tab buttons row lives.

- [ ] **Step 1: Locate the tab nav row**

Run:
```sh
grep -rn "coordinator.currentView = .home\|coordinator.currentView = .codingAgents" DynamicIsland/components/Notch DynamicIsland/ContentView.swift
```

The matches show where tab-switch buttons live. The most likely file is `DynamicIslandHeader.swift` (line 280 sets `.home`), but inspect each hit to find the one that's a row of tappable tab icons, NOT a one-off action elsewhere (e.g., Task 9 in the codebase already gates a `.shelf` switch in `ContentView.swift:1889` which is a drop handler, not nav).

- [ ] **Step 2: Add a Weather button mirroring the existing tab button pattern**

Once located, mirror the pattern of the `.codingAgents` tab button. The exact code depends on the file's structure, but it should look approximately like:

```swift
if Defaults[.enableNotchWeather] {
    Button {
        coordinator.currentView = .weather
    } label: {
        Image(systemName: "cloud.sun.fill")
            .symbolRenderingMode(.hierarchical)
    }
    .buttonStyle(.plain)
    .help("Weather")
}
```

Place it right after the `.codingAgents` button. **If the file uses a different button factory (e.g. a `TabButton(view: .codingAgents, icon: …)` helper), use that instead** — match the existing style 1:1 so it doesn't look out of place.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test**

Cmd-R. Hover the notch open. You should see a new Weather tab button in the tab row. Click it. The Weather tab should render. Check that:
- The hero shows your city, temp, and a condition (after granting location if asked)
- The hourly strip scrolls horizontally without closing the notch
- The 7-day list shows under it

If the strip closes the notch on scroll, double-check Step 7 of Task 7 — the suppression calls must fire on hover.

- [ ] **Step 5: Commit**

```sh
git add <the file you modified>
git commit -m "feat: add weather tab button to notch nav"
```

---

## Task 10: Create the `WeatherSettings` pane

**Files:**
- Create: `DynamicIsland/components/Settings/WeatherSettings.swift`

- [ ] **Step 1: Create the settings view**

Create `DynamicIsland/components/Settings/WeatherSettings.swift` with this exact content:

```swift
/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import CoreLocation
import Defaults
import SwiftUI

struct WeatherSettings: View {
    @Default(.enableNotchWeather) private var enabled
    @Default(.lockScreenWeatherTemperatureUnit) private var unit
    @Default(.lockScreenWeatherProviderSource) private var providerSource
    @StateObject private var manager = NotchWeatherManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Weather tab in the notch", isOn: $enabled)
            } footer: {
                Text("When enabled, a Weather tab appears alongside Home, Shelf, and other tabs in the open notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Units") {
                Picker("Temperature", selection: $unit) {
                    ForEach(LockScreenWeatherTemperatureUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("This setting is shared with the lock-screen weather widget. Wind speed follows the chosen unit (km/h with Celsius, mph with Fahrenheit).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data Source") {
                Picker("Provider", selection: $providerSource) {
                    ForEach(LockScreenWeatherProviderSource.allCases) { src in
                        Text(src.displayName).tag(src)
                    }
                }
            } footer: {
                Text("Open-Meteo is free and requires no key. wttr.in is a community service. The notch tab currently uses Open-Meteo; this setting also applies to the lock-screen widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                HStack {
                    Image(systemName: locationStatusSymbol)
                        .foregroundStyle(locationStatusTint)
                    Text(locationStatusText)
                    Spacer()
                    if locationStatus == .denied || locationStatus == .restricted {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Button("Refresh now") {
                        manager.refreshNow()
                    }
                    if let last = manager.lastRefresh {
                        Text("Last refresh: \(last, format: .relative(presentation: .numeric))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Location status helpers

    private var locationStatus: CLAuthorizationStatus {
        CLLocationManager.authorizationStatus()
    }

    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Location access granted"
        case .denied:        return "Location access denied"
        case .restricted:    return "Location access restricted by system"
        case .notDetermined: return "Location permission not yet requested"
        @unknown default:    return "Unknown location permission state"
        }
    }

    private var locationStatusSymbol: String {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "checkmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var locationStatusTint: Color {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .green
        default: return .orange
        }
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```sh
git add DynamicIsland/components/Settings/WeatherSettings.swift
git commit -m "feat: add WeatherSettings pane"
```

---

## Task 11: Register `weather` in `SettingsTab` enum

**Files:**
- Modify: `DynamicIsland/components/Settings/SettingsView.swift:48-172` (multiple switch statements)

- [ ] **Step 1: Add the enum case**

In `SettingsView.swift`, the `private enum SettingsTab: String, CaseIterable, Identifiable` starts at line 48. Add `case weather` to the list (alphabetical-ish, place it near other top-level system tabs):

```swift
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case lockScreen
    case weather   // ← NEW
    case media
    …
```

- [ ] **Step 2: Add the `.weather` branch in `group`**

In the `var group: SettingsTabGroup` switch (line ~77):

```swift
case .media, .liveActivities, .lockScreen, .devices:                 return .mediaAndDisplay
```

Change to:

```swift
case .media, .liveActivities, .lockScreen, .devices, .weather:       return .mediaAndDisplay
```

(Weather belongs in Media & Display alongside the lock-screen widget.)

- [ ] **Step 3: Add the `.weather` branch in `title`**

In the `var title: String` switch (line ~90):

```swift
case .weather: return String(localized: "Weather")
```

Add this line wherever feels natural in the list.

- [ ] **Step 4: Add the `.weather` branch in `systemImage`**

In the `var systemImage: String` switch (line ~118):

```swift
case .weather: return "cloud.sun.fill"
```

- [ ] **Step 5: Add the `.weather` branch in `tint`**

In the `var tint: Color` switch (line ~146):

```swift
case .weather: return Color(red: 0.30, green: 0.70, blue: 0.95)
```

- [ ] **Step 6: Route `.weather` to `WeatherSettings()` in the content area**

In `SettingsView.swift`, locate the routing switch (search for `case .codingAgents:` to find the right block — it'll be a switch on `SettingsTab` that returns the destination view). Add:

```swift
case .weather:
    WeatherSettings()
```

If you don't find this routing switch on first grep, run:
```sh
grep -n "CodingAgentsSettings()" DynamicIsland/components/Settings/SettingsView.swift
```
That hit identifies the switch. Add the `.weather` branch right next to `.codingAgents`'s.

- [ ] **Step 7: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If a switch is still non-exhaustive, the error tells you which one — add `.weather` to that one too.

- [ ] **Step 8: Manual smoke test**

Cmd-R. Open Settings (menu bar → Isle icon → Settings). In the sidebar under "Media & Display", you should see a new "Weather" row with a cloud.sun.fill icon. Click it. Toggle the master switch off and on — the Weather tab in the notch should appear/disappear (test by opening the notch).

Change the temperature unit — the lock-screen widget should reflect it next time you lock the screen (the notch tab updates immediately because the manager listens on the same Defaults key).

- [ ] **Step 9: Commit**

```sh
git add DynamicIsland/components/Settings/SettingsView.swift
git commit -m "feat: add Weather settings pane to Settings sidebar"
```

---

## Task 12: Gate the tab nav button on the master toggle

**Files:**
- Modify: the file you found in Task 9

- [ ] **Step 1: Verify the gate**

Re-open the file you modified in Task 9. The button you added should already be wrapped in `if Defaults[.enableNotchWeather] { … }`. If it isn't (e.g. the codebase's tab nav uses a different gating pattern), wrap it now.

- [ ] **Step 2: Smoke test**

Cmd-R. Open Settings → Weather → toggle "Show Weather tab in the notch" off. Hover the notch open. The Weather tab button should be gone. Toggle it back on — it reappears.

- [ ] **Step 3: Commit (only if Step 1 required a change)**

```sh
git add <the file>
git commit -m "feat: gate weather tab nav button on enableNotchWeather"
```

---

## Task 13: Full integration smoke test

No file changes — this is purely manual verification of the spec's checklist.

- [ ] **Step 1: Lock-screen widget regression check**

Lock the screen (Ctrl-Cmd-Q). The weather widget should still display temperature, symbol, and any other elements it had before (battery, AQI, etc., depending on your settings). Unlock.

- [ ] **Step 2: Weather tab — happy path**

Open notch → click Weather tab. Expect:
- City name in the header (or empty if reverse-geocoding failed — that's acceptable)
- "Updated Xs ago" relative time
- Hero with temperature, condition icon, condition text, feels-like / wind / humidity
- Hourly strip with 12 entries; scrolls horizontally without closing the notch
- 7-day list with min/max bars; "Today" as first label, then "Sat", "Sun", etc.

- [ ] **Step 3: Refresh button**

Click the ↻ button in the header. Spinner animates. New "Updated Xs ago" updates.

- [ ] **Step 4: Unit switch propagates**

Settings → Weather → change Celsius ↔ Fahrenheit. Notch tab should update its temperatures immediately (the manager listens on the Defaults key and refetches).

- [ ] **Step 5: Permission denied UX**

Open System Settings → Privacy & Security → Location Services. Find Isle and toggle it off. Re-open the Weather tab. You should see the `location.slash` icon, the "Location access needed" message, and a button that opens System Settings.

Re-enable the location access for Isle before continuing.

- [ ] **Step 6: Tab disabled UX**

Settings → Weather → toggle the master switch off. Open notch. Weather tab button is gone. Toggle back on. Re-appears.

- [ ] **Step 7: Other tabs still work**

Click through Home, Shelf, Agents, etc. — no regressions.

- [ ] **Step 8: Commit (no file changes — this step is the manual sign-off)**

If everything passed, no commit needed. If you found anything off, fix it in a follow-up commit and re-run this checklist.

---

## Verification Checklist (per spec)

After all tasks, confirm each item from the spec's verification section:

- [ ] Lock-screen weather widget still works after the extraction refactor
- [ ] Weather tab visible in the open notch when `enableNotchWeather = true`
- [ ] Hover over scrollable hourly strip does NOT close the notch
- [ ] Hourly scroll itself works (12 cells, horizontal)
- [ ] Daily list renders 7 days with min/max bars correctly scaled
- [ ] Permission denied → "Open Settings" deep-link works
- [ ] Network error → retry button refetches (test by toggling Wi-Fi off, clicking Retry, then Wi-Fi on, clicking Retry again)
- [ ] Changing the unit in Settings updates the tab immediately AND the lock-screen widget on next refresh
- [ ] No regressions in other tabs (Home, Shelf, Agents)
