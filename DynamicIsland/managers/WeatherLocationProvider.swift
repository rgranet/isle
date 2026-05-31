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
