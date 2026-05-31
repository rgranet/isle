/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Defaults
import SwiftUI

/// Open-notch Weather tab. Three sections: hero (current), hourly scroll,
/// 7-day daily list. Handles loading / location-denied / error states.
///
/// Layout note: the root MUST stay `VStack(spacing: 0)` with no root padding
/// and `.frame(maxWidth: .infinity, maxHeight: .infinity)` (no alignment), so
/// the notch keeps its rounded silhouette. Padding lives inside each section.
struct NotchWeatherView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var manager = NotchWeatherManager.shared
    @Default(.lockScreenWeatherTemperatureUnit) private var unit

    @State private var hoverSuppressionToken = UUID()
    @State private var refreshSpinning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 6) {
            if let city = manager.placeName, !city.isEmpty {
                Image(systemName: "location.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.85))
                Text(city)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            if let last = manager.lastRefresh {
                Text("Updated \(last, format: .relative(presentation: .numeric))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
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
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: Content — switches on state

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle:
            loadingPlaceholder
        case .loading where manager.current == nil:
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if let current = manager.current {
                    heroRow(current)
                }
                if !manager.hourly.isEmpty {
                    hourlyStrip
                }
                if !manager.daily.isEmpty {
                    dailyList
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: Hero

    private func heroRow(_ current: NotchCurrentWeather) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Glowing icon badge in a brand-tinted circle backdrop
            ZStack {
                Circle()
                    .fill(conditionTint(for: current).opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: current.symbolName)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.white)
                    .shadow(color: conditionTint(for: current).opacity(0.5), radius: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(round(current.temperature)))°")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(temperatureGradient(for: current.temperature))
                    Text(current.conditionText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(conditionTint(for: current))
                        .lineLimit(1)
                }
                Text(secondaryLine(for: current))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
            HStack(spacing: 14) {
                ForEach(manager.hourly) { hour in
                    VStack(spacing: 4) {
                        Text(hour.id, format: .dateTime.hour())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: hour.symbolName)
                            .font(.system(size: 16))
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.white)
                            .frame(height: 20)
                        Text("\(Int(round(hour.temperature)))°")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(temperatureGradient(for: hour.temperature))
                    }
                    .frame(minWidth: 30)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: Daily list

    private var dailyList: some View {
        let range = weeklyTempRange()
        return VStack(spacing: 4) {
            ForEach(Array(manager.daily.enumerated()), id: \.element.id) { idx, day in
                HStack(spacing: 10) {
                    Text(dayLabel(for: day.id, index: idx))
                        .font(.system(size: 12, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundStyle(idx == 0 ? Color.white : Color.white.opacity(0.78))
                        .frame(width: 42, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .font(.system(size: 14))
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(.white)
                        .frame(width: 20)
                    Text("\(Int(round(day.minTemp)))°")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.85))
                        .frame(width: 26, alignment: .trailing)
                        .monospacedDigit()
                    rangeBar(min: day.minTemp, max: day.maxTemp, weekRange: range)
                        .frame(height: 5)
                    Text("\(Int(round(day.maxTemp)))°")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.95))
                        .frame(width: 26, alignment: .leading)
                        .monospacedDigit()
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
            let w = max(3, proxy.size.width * CGFloat(endFrac - startFrac))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.75, blue: 1.00),  // cool blue
                                Color(red: 0.36, green: 0.85, blue: 0.55),  // green
                                Color(red: 1.00, green: 0.83, blue: 0.32),  // yellow
                                Color(red: 1.00, green: 0.55, blue: 0.20),  // orange
                                Color(red: 0.95, green: 0.30, blue: 0.25)   // red
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: w)
                    .offset(x: x)
                    .shadow(color: .orange.opacity(0.25), radius: 2, y: 1)
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

    // MARK: Color logic

    /// Tints temperature numbers with a gradient based on how warm it is.
    /// The user-selected unit decides the thresholds: Celsius uses ~SI bands,
    /// Fahrenheit converts the same boundaries.
    private func temperatureGradient(for temp: Double) -> LinearGradient {
        let isCelsius = unit.usesMetricSystem
        let cold: Double  = isCelsius ? 5   : 41   // <= cold
        let mild: Double  = isCelsius ? 15  : 59
        let warm: Double  = isCelsius ? 23  : 73
        let hot:  Double  = isCelsius ? 30  : 86

        let colors: [Color]
        switch temp {
        case ..<cold:
            colors = [Color(red: 0.45, green: 0.85, blue: 1.00),
                      Color(red: 0.25, green: 0.65, blue: 1.00)]
        case cold..<mild:
            colors = [Color(red: 0.55, green: 0.95, blue: 0.95),
                      Color(red: 0.35, green: 0.85, blue: 0.75)]
        case mild..<warm:
            colors = [Color(red: 0.70, green: 1.00, blue: 0.60),
                      Color(red: 0.95, green: 0.95, blue: 0.55)]
        case warm..<hot:
            colors = [Color(red: 1.00, green: 0.88, blue: 0.45),
                      Color(red: 1.00, green: 0.65, blue: 0.30)]
        default:
            colors = [Color(red: 1.00, green: 0.55, blue: 0.30),
                      Color(red: 0.95, green: 0.30, blue: 0.25)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Brand tint matching the current condition. Sun-bright in clear skies,
    /// deep blue in rain, neutral in cloud, indigo at night.
    private func conditionTint(for current: NotchCurrentWeather) -> Color {
        if !current.isDaytime {
            return Color(red: 0.55, green: 0.55, blue: 0.95) // indigo
        }
        switch current.weatherCode {
        case 0, 1:           return Color(red: 1.00, green: 0.82, blue: 0.30) // sunny yellow
        case 2, 3:           return Color(red: 0.78, green: 0.85, blue: 0.95) // pale cloud
        case 45, 48:         return Color(red: 0.65, green: 0.70, blue: 0.80) // fog grey
        case 51...67, 80...82: return Color(red: 0.35, green: 0.70, blue: 1.00) // rain blue
        case 71...77, 85, 86:  return Color(red: 0.85, green: 0.92, blue: 1.00) // snow
        case 95...99:          return Color(red: 0.65, green: 0.45, blue: 1.00) // thunder violet
        default:               return Color(red: 0.75, green: 0.80, blue: 0.95)
        }
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
                .foregroundStyle(.orange)
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
                .foregroundStyle(.orange.opacity(0.8))
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
