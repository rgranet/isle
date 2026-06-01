/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Combine
import Defaults
import Foundation

/// Periodically polls the Dock's AX tree to surface unread badge counts
/// for the messaging apps Isle supports (WhatsApp, Teams, Slack, iMessage).
///
/// Drives:
///   • the closed-notch indicator (MessagingLiveActivity)
///   • the Messages tab (NotchMessagesView)
///   • the Settings panel status section
@MainActor
final class MessagingAppMonitor: ObservableObject {
    static let shared = MessagingAppMonitor()

    /// `[app: parsed unread count]`. Only contains entries with count > 0.
    /// Apps that aren't running, aren't enabled, or have no badge are
    /// absent (not present with 0) so observers can rely on
    /// `isEmpty == nothing to show`.
    @Published private(set) var unreadCounts: [MessagingApp: Int] = [:]

    /// Last successful poll timestamp — used by Settings to show "updated
    /// 3 s ago" so the user can tell the polling loop is alive.
    @Published private(set) var lastPolledAt: Date?

    /// True when at least one monitored app currently shows a badge.
    var hasUnread: Bool { !unreadCounts.isEmpty }

    /// Total across all monitored apps. Useful for the collapsed-island
    /// "+N" overflow indicator.
    var totalUnread: Int { unreadCounts.values.reduce(0, +) }

    /// Returns the apps with unread, ordered by descending count then
    /// alphabetical so the UI is stable from poll to poll.
    var unreadSorted: [(app: MessagingApp, count: Int)] {
        unreadCounts
            .map { (app: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.app.displayName < rhs.app.displayName
                }
                return lhs.count > rhs.count
            }
    }

    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.enableMessagingApps)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleEnabledChange(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.messagingPollingInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restartPollingIfNeeded()
            }
            .store(in: &cancellables)

        if Defaults[.enableMessagingApps] {
            startPolling()
        }
    }

    // MARK: Polling lifecycle

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            startPolling()
        } else {
            stopPolling()
            unreadCounts = [:]
        }
    }

    private func restartPollingIfNeeded() {
        guard Defaults[.enableMessagingApps] else { return }
        stopPolling()
        startPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let interval = max(1.0, Defaults[.messagingPollingInterval])
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Public manual refresh hook (used by the Settings "Refresh now"
    /// button and by the Messages tab on appear).
    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: Refresh

    private func refresh() async {
        // Reading AX is synchronous and fast (<5 ms typical). Detach so
        // the main actor never blocks on it.
        let badges = await Task.detached {
            DockBadgeReader.readAllBadges()
        }.value

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        var result: [MessagingApp: Int] = [:]
        for app in MessagingApp.allCases {
            guard Defaults[app.enabledDefaultsKey] else { continue }
            // Skip apps that aren't running — avoids stale badges from
            // a previous launch that the Dock might still surface.
            let isRunning = app.bundleIDs.contains { runningBundleIDs.contains($0) }
            guard isRunning else { continue }

            // Look up the dock tile by title. macOS uses the same
            // localized display name in the Dock as in the menu bar.
            // Try each known variant (e.g. "Discord", "Discord Canary")
            // and take the first match.
            guard let badge = app.dockTitles.lazy.compactMap({ badges[$0] }).first else { continue }
            if let count = parsedCount(from: badge), count > 0 {
                result[app] = count
            } else if !badge.isEmpty, app.acceptsNonNumericBadge {
                // Some apps render a non-numeric badge (e.g. "●" or "!");
                // count as 1 so we still surface the indicator. Discord
                // opts out: its numeric badge is DMs/mentions only, and
                // the non-numeric dot fires for any unread server channel
                // — far too noisy to surface in the notch.
                result[app] = 1
            }
        }

        if result != unreadCounts {
            // v1.2 — detect a fresh arrival (new app appears OR existing
            // app's count goes up) and puff the notch like the volume HUD.
            // Done BEFORE we replace `unreadCounts` so we can diff cleanly.
            if Defaults[.messagingGrowNotchOnArrival] {
                triggerArrivalExpansionIfNeeded(previous: unreadCounts, current: result)
            }
            unreadCounts = result
        }
        lastPolledAt = .now
    }

    /// Picks the app with the largest "delta upward" between the two
    /// snapshots and pushes a single `codingAgentArrived`-style expansion
    /// for it. One puff per refresh cycle even when several apps moved.
    private func triggerArrivalExpansionIfNeeded(
        previous: [MessagingApp: Int],
        current: [MessagingApp: Int]
    ) {
        var bestDelta = 0
        var bestApp: MessagingApp?
        var bestCount = 0
        for (app, count) in current {
            let prev = previous[app] ?? 0
            let delta = count - prev
            if delta > bestDelta {
                bestDelta = delta
                bestApp = app
                bestCount = count
            }
        }
        guard let app = bestApp else { return }
        DynamicIslandViewCoordinator.shared.toggleExpandingView(
            status: true,
            type: .messagingArrived(appID: app.rawValue, count: bestCount),
            autoHideDuration: 3.0
        )
    }

    private func parsedCount(from badge: String) -> Int? {
        // Strip non-digit characters ("12+", "1.234", "12 unread").
        let digits = badge.filter(\.isNumber)
        return Int(digits)
    }

    // MARK: Helpers exposed to UI

    /// Activate the app's window. Used by the "Open" button in the
    /// Messages tab. No-op if the app is not running.
    func activate(_ app: MessagingApp) {
        let running = NSWorkspace.shared.runningApplications
        for candidate in running {
            guard let id = candidate.bundleIdentifier, app.bundleIDs.contains(id) else {
                continue
            }
            candidate.activate(options: [.activateIgnoringOtherApps])
            return
        }
    }
}
