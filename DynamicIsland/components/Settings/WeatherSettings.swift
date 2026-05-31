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

            Section {
                Picker("Temperature", selection: $unit) {
                    ForEach(LockScreenWeatherTemperatureUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Units")
            } footer: {
                Text("This setting is shared with the lock-screen weather widget. Wind speed follows the chosen unit (km/h with Celsius, mph with Fahrenheit).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Provider", selection: $providerSource) {
                    ForEach(LockScreenWeatherProviderSource.allCases) { src in
                        Text(src.displayName).tag(src)
                    }
                }
            } header: {
                Text("Data Source")
            } footer: {
                Text("Open-Meteo is free and requires no key. wttr.in is a community service. The notch tab currently uses Open-Meteo; this setting also applies to the lock-screen widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
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
            } header: {
                Text("Location")
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
