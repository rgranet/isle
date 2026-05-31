# Weather notch tab — design spec

**Date:** 2026-05-31
**Status:** Approved by user, ready for implementation plan

## Summary

Add a dedicated `Weather` tab to the open-notch view alongside Home / Shelf /
Tray / Agents. Reuses the existing Open-Meteo + wttr.in infrastructure that
already powers the lock-screen weather widget. No WeatherKit, no entitlement
changes, no Developer Portal config.

The tab shows:
- Current conditions (city, large temperature, weather icon, condition text,
  feels-like / wind / humidity)
- 12-hour horizontal scroll strip
- 7-day forecast list with min/max range bars

## Why reuse, not WeatherKit

Initial brainstorm picked WeatherKit, then we discovered the codebase
already ships a complete Open-Meteo + wttr.in implementation in
`DynamicIsland/managers/LockScreenWeatherManager.swift` (≈1140 lines). It
includes location handling, symbol mapping, day/night switching, and a
fallback chain. Switching to WeatherKit would mean:

- Adding the `com.apple.developer.weatherkit` entitlement to both bundle IDs
- Registering WeatherKit capability on developer.apple.com for
  `com.withmii.isle` and `com.withmii.isle.dev`
- Waiting ~30 min for portal propagation
- Maintaining two weather pipelines in parallel

For zero user-visible benefit (data accuracy is comparable, attribution
requirements are similar). Reusing what exists is the right call.

## Architecture

### Existing code to extract (refactor)

The lock-screen file currently keeps these utilities `private`. Lift them to
module-internal so the new tab can use them:

| Current location | New location | Change |
|---|---|---|
| `LockScreenWeatherManager.swift:1091` `LockScreenWeatherLocationProvider` | `managers/WeatherLocationProvider.swift` | Rename, `internal` visibility, hosted as a shared singleton or DI target |
| `LockScreenWeatherManager.swift:1013` `OpenMeteoSymbolMapper` | `managers/WeatherSymbolMappers.swift` | Move, keep enum |
| `LockScreenWeatherManager.swift:1050` `WeatherSymbolMapper` | Same | Move |
| `LockScreenWeatherManager.swift:1075` `symbolAdjustedForDaylight` | Same | Move as `internal` function |

`LockScreenWeatherManager` keeps its own copies of `LockScreenWeatherSnapshot`
and its provider — those are coupled to the lock-screen widget's many side
features (battery, bluetooth, AQI, calendar interplay). We don't unify the
snapshot models.

### New code

**`DynamicIsland/managers/NotchWeatherManager.swift`** — `@MainActor` singleton
- `@Published var current: CurrentWeather?`
- `@Published var hourly: [HourlyForecast]` (12 entries)
- `@Published var daily: [DailyForecast]` (7 entries)
- `@Published var placeName: String?`
- `@Published var lastRefresh: Date?`
- `@Published var state: LoadState` (`.idle / .loading / .ready / .error(Error) / .locationDenied`)
- `func refreshIfStale()` — only fetches if `lastRefresh > 15min`
- `func refreshNow()` — bypasses the freshness check
- Uses shared `WeatherLocationProvider`
- Calls one Open-Meteo endpoint with `current,hourly,daily` params + 7 days
- Reverse-geocodes via `CLGeocoder` for `placeName` (cached, only on location
  change). On geocoder failure, falls back to displaying nothing in the city
  slot (the rest of the UI stays functional)

**`DynamicIsland/components/Notch/NotchWeatherView.swift`** — the tab UI
- Three vertical sections: hero / hourly strip / daily list
- Hero: city + temp + icon + condition + secondary line (feels-like · wind · humidity)
- Hourly: `ScrollView(.horizontal)` of 12 `HourCell` (time, icon, temp)
- Daily: `VStack` of 7 `DayRow` (weekday short, icon, min, range bar, max)
- States: `.loading` → ProgressView, `.error` → retry button, `.locationDenied`
  → "Open Settings" button, `.ready` → the three sections
- `.onAppear { manager.refreshIfStale() }`
- `.onAppear` calls `vm.setScrollGestureSuppression(true, token:)` and
  `vm.setAutoCloseSuppression(true, token:)`; `.onDisappear` releases both
  (per CLAUDE.md gotcha #2)

**`DynamicIsland/components/Settings/WeatherSettings.swift`** — Settings pane
- Master toggle (`enableNotchWeather`)
- Units picker — **reuses `Defaults[.lockScreenWeatherTemperatureUnit]`** so
  changing the unit affects both widgets
- Provider source — **reuses `Defaults[.lockScreenWeatherProviderSource]`**
  (Open-Meteo / wttr.in)
- Location permission status row + "Open System Settings" button
- "Refresh now" button

### Wiring

**`enums/generic.swift`**
- Add `case weather` to `NotchViews`

**`ContentView.swift`** (or wherever the tab dispatcher lives)
- Add a branch rendering `NotchWeatherView()` when `coordinator.currentView == .weather`

**Tab nav** — wherever Home/Shelf/Agents are listed, append a "Weather" entry
gated on `Defaults[.enableNotchWeather]`. Mirror how `.codingAgents` was added.

**`models/Constants.swift`**
- `extension Defaults.Keys { static let enableNotchWeather = Key<Bool>("enableNotchWeather", default: true) }`

**`components/Settings/SettingsView.swift`**
- Add a `.weather` case to the Settings tab enum, route to `WeatherSettings()`

## Data model

```swift
struct CurrentWeather: Equatable {
    let temperature: Double           // in user-selected unit
    let apparentTemperature: Double?  // "feels like"
    let weatherCode: Int              // WMO code
    let isDaytime: Bool
    let windSpeed: Double             // km/h or mph matching unit
    let humidity: Int                 // percent
    let symbolName: String            // pre-resolved with day/night
    let conditionText: String
}

struct HourlyForecast: Identifiable, Equatable {
    let id: Date  // the hour
    let temperature: Double
    let weatherCode: Int
    let isDaytime: Bool
    let symbolName: String
}

struct DailyForecast: Identifiable, Equatable {
    let id: Date  // the day (midnight local)
    let weatherCode: Int
    let symbolName: String
    let minTemp: Double
    let maxTemp: Double
}

enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case locationDenied
    case error(String)  // localized description
}
```

## Open-Meteo request

Single GET to `https://api.open-meteo.com/v1/forecast`:

```
latitude=…&longitude=…
&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m
&hourly=temperature_2m,weather_code,is_day
&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset
&forecast_days=7
&timezone=auto
&temperature_unit=celsius|fahrenheit  (per Defaults)
&wind_speed_unit=kmh|mph              (matches temp unit)
```

Hourly: keep only the next 12 entries starting from the current hour.
Daily: keep the first 7 entries (today + 6 days ahead).

## Visual layout

```
┌────────────────────────────────────────────────────┐
│  Paris                          Updated 2m ago  ↻ │ ← header
│                                                    │
│   🌤  21°            Partly cloudy                │ ← hero
│       Feels 19° · Wind 12 km/h · Humidity 64%     │
│                                                    │
│  ─────────────────────────────────────────────    │
│  Now  10  11  12  13  14  15  16  17  18  19  20  │
│  21°  22  22  23  24  24  23  22  20  18  17  16  │ ← horaire
│  🌤  🌤  ☀️  ☀️  ☀️  ⛅️  ⛅️  ⛅️  🌧  🌧  🌧  🌙   │
│  ─────────────────────────────────────────────    │
│  Today    🌤   14°  ────●━━━━━━●────  24°          │ ← daily
│  Sat      ☀️   15°  ────●━━━━━━━●───  26°          │
│  Sun      ⛅️   13°  ────●━━━━━●─────  22°          │
│  Mon      🌧   11°  ──●━━━●─────────  17°          │
│  …                                                  │
└────────────────────────────────────────────────────┘
```

Header right side: relative-time text + a refresh icon button. Spinner state
on the button while a fetch is in flight.

Range bar in daily rows uses the global min/max of the week as the bar's
domain so the dots are comparable across days.

## Non-nominal states

| State | Visual |
|---|---|
| Loading initial | Centered ProgressView + "Fetching weather…" |
| `locationDenied` | `location.slash` icon + "Location access needed" + "Open Settings" button (opens `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`) |
| `error(_)` | `cloud.slash` icon + localized error + "Retry" button |
| Geoloc pending | "Locating…" with spinner (5s max before falling through to error) |
| Tab disabled in Settings | Tab hidden from the tab selector — no visible entry |

## Freshness behavior

- Auto-refresh when the user opens the Weather tab AND `lastRefresh > 15min`
  (`refreshIfStale()`)
- Manual refresh button in the header
- No background polling — battery + bandwidth conscious. Stale data shown
  until next open is fine; relative-time text in header signals staleness

## Units

- Default: `auto` → metric if `Locale.current.measurementSystem == .metric`,
  imperial otherwise
- User override in Settings: Celsius / Fahrenheit / Auto
- Wind unit follows: km/h with Celsius, mph with Fahrenheit
- Humidity in percent (no unit choice)
- Pressure not displayed (space)

## Gotchas (per CLAUDE.md section 7)

1. **Scroll inside notch closes it** — `NotchWeatherView` must call
   `vm.setScrollGestureSuppression(true, token:)` and
   `vm.setAutoCloseSuppression(true, token:)` on hover, release on disappear.
2. **No hover-blocking shapes** — irrelevant here because this is an
   open-notch tab view, not a closed-notch live activity. Skip.
3. **Synchronized Xcode groups** — new `.swift` files dropped into
   `managers/` and `components/Notch/` are auto-picked-up. No pbxproj edit.

## Out of scope (deferred)

- Closed-notch weather indicator (always-visible temp capsule) — could be a
  v1.next addition; not in this spec
- Weather alerts / push notifications — not provided by Open-Meteo free tier
- Multi-location support — only "where you are now"
- Pressure, UV index, sunrise/sunset in the tab (sunrise stays in lock-screen
  widget where the layout supports it)
- Animated weather backgrounds (rain particles, etc.)
- Air quality in the tab (lock-screen widget keeps AQI; tab stays focused on
  temp + forecast)

## Implementation order

1. Extract shared utilities (`WeatherLocationProvider`, mappers) without
   breaking `LockScreenWeatherManager`. Build + smoke test.
2. Add `NotchWeatherManager`, fetch, model. Unit-testable in isolation.
3. Build `NotchWeatherView` with all states.
4. Wire `NotchViews.weather`, tab nav, ContentView dispatch.
5. Build `WeatherSettings` pane, hook into `SettingsView`.
6. Integration smoke test: open notch → click Weather tab → verify data,
   verify refresh button, verify Settings unit change propagates.

## Verification checklist

- [ ] Lock-screen weather widget still works after the extraction refactor
- [ ] Weather tab visible in the open notch when `enableNotchWeather = true`
- [ ] Hover over scrollable hourly strip does NOT close the notch
- [ ] Hourly scroll itself works (12 cells, horizontal)
- [ ] Daily list renders 7 days with min/max bars correctly scaled
- [ ] Permission denied → "Open Settings" deep-link works
- [ ] Network error → retry button refetches
- [ ] Changing the unit in Settings updates the tab immediately AND the
      lock-screen widget on next refresh
- [ ] No regressions in other tabs (Home, Shelf, Agents)
