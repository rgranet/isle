/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Defaults
import SwiftUI

/// Settings panel for the v1.1 messaging-app monitor. Master toggle, poll
/// cadence, per-app on/off, and a live status section showing the latest
/// dock-badge counts so the user can verify the monitor is reading.
struct MessagingSettings: View {
    @ObservedObject private var monitor = MessagingAppMonitor.shared

    @Default(.enableMessagingApps) private var enabled
    @Default(.messagingPollingInterval) private var pollInterval
    @Default(.messagingShowClosedNotchIndicator) private var showClosedIndicator

    var body: some View {
        Form {
            masterSection
            if enabled {
                discoverySection
                appearanceSection
                appsSection
                statusSection
                accessibilitySection
            }
        }
        .formStyle(.grouped)
    }

    private var masterSection: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show messaging app notifications in the notch")
                        .font(.body)
                    Text("Watches the Dock badge of WhatsApp, Microsoft Teams, Slack and Messages. Surfaces unread counts in a dedicated Messages tab and (optionally) a brand-colored dot when the notch is closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var discoverySection: some View {
        Section("Discovery") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(Int(pollInterval)) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $pollInterval, in: 2...30, step: 1)
                Text("How often Isle re-reads dock badges. Cheap on CPU (~5 ms per poll).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh now") {
                monitor.refreshNow()
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Show indicator in the closed notch when any app has unread messages", isOn: $showClosedIndicator)
        }
    }

    private var appsSection: some View {
        Section {
            ForEach(MessagingApp.allCases) { app in
                MessagingAppToggleRow(app: app)
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("Each app is independently togglable. Disabled apps don't appear in the Messages tab and don't contribute to the closed-notch indicator.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.tertiary)
                Text("Total unread across all monitored apps")
                Spacer()
                Text("\(monitor.totalUnread)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let polledAt = monitor.lastPolledAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.tertiary)
                    Text("Last polled")
                    Spacer()
                    Text(polledAt, style: .relative)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if !monitor.unreadCounts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(monitor.unreadSorted, id: \.app.id) { entry in
                        HStack {
                            Circle()
                                .fill(Color(isleHex: entry.app.brandColorHex))
                                .frame(width: 8, height: 8)
                            Text(entry.app.displayName)
                                .font(.callout)
                            Spacer()
                            Text("\(entry.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var accessibilitySection: some View {
        // TimelineView re-evaluates this section every 2 seconds so that
        // when the user grants Accessibility permission in System Settings
        // the section flips from "missing" → "granted" without needing to
        // close and reopen this window. Free, no Combine wiring.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Section {
                if DockBadgeReader.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Accessibility permission granted")
                            .font(.callout)
                        Spacer()
                    }
                } else {
                    accessibilityMissingBlock
                }
            } header: {
                Text("Permissions")
            }
        }
    }

    @ViewBuilder
    private var accessibilityMissingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility permission required")
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            Text("Isle needs Accessibility access to read dock badges. Without it, all monitored apps will show zero unread messages even when they have notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Show the exact bundle ID the user needs to grant — Debug
            // builds (`com.withmii.isle.dev`) and Release builds
            // (`com.withmii.isle`) are TWO DIFFERENT entries in the
            // Accessibility list. Granting one doesn't grant the other.
            if let bundleID = Bundle.main.bundleIdentifier {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Look for")
                        .font(.caption)
                    Text(bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                    Text("in the list.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }

                // macOS often refuses to propagate a freshly-granted TCC
                // permission to the already-running process. A quit +
                // relaunch via the app's own bundle URL is the reliable
                // way to make the new permission stick.
                Button("Restart Isle") {
                    restartIsle()
                }
                .help("Quits Isle and relaunches it so macOS propagates the new permission.")
            }

            // Diagnostic — shows whether the TCC trust flag and the
            // functional AX query agree. If trusted=true but functional=false
            // the TCC entry is stale: best fix is to remove the entry and
            // re-add it (or `tccutil reset Accessibility <bundle id>`).
            let diag = DockBadgeReader.diagnostic()
            Text("Diagnostic — trusted: \(diag.trusted ? "yes" : "no"), functional: \(diag.functional ? "yes" : "no"), dock badges found: \(diag.dockBadgesFound)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            if diag.trusted && !diag.functional {
                Text("TCC entry looks stale. In Terminal, run:  tccutil reset Accessibility \(Bundle.main.bundleIdentifier ?? "com.withmii.isle.dev")  — then re-grant permission.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    private func restartIsle() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSApplication.shared.terminate(nil)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct MessagingAppToggleRow: View {
    let app: MessagingApp

    @State private var enabled: Bool = true

    var body: some View {
        Toggle(isOn: $enabled) {
            HStack(spacing: 8) {
                if NSImage(named: app.iconAssetName) != nil {
                    Image(app.iconAssetName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(isleHex: app.brandColorHex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: app.fallbackSymbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
                Text(app.displayName)
            }
        }
        .onAppear {
            enabled = Defaults[app.enabledDefaultsKey]
        }
        .onChange(of: enabled) { _, newValue in
            Defaults[app.enabledDefaultsKey] = newValue
        }
    }
}
