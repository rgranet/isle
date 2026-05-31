/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version. See LICENSE.
 */

import Defaults
import IsleCore
import SwiftUI

/// Settings panel for the Isle coding-agent integration.
///
/// **M7 status**: master toggle + polling cadence + per-agent install/uninstall
/// surface. Per-agent install actually invokes the underlying installer (for
/// the agents whose installers are ported). UI states are derived from
/// `AgentSessionStore.shared` for live counts.
struct CodingAgentsSettings: View {
    @ObservedObject private var store = AgentSessionStore.shared

    @Default(.enableCodingAgents) private var enableCodingAgents
    @Default(.codingAgentsPollingInterval) private var pollingInterval
    @Default(.codingAgentsShowClosedNotchIndicator) private var showClosedIndicator
    @Default(.codingAgentsSoundEnabled) private var soundEnabled
    @Default(.codingAgentsPermissionTimeoutSeconds) private var permissionTimeoutSeconds
    @Default(.codingAgentsHistoryLimit) private var historyLimit

    @State private var feedback: String?

    var body: some View {
        Form {
            masterSection
            if enableCodingAgents {
                discoverySection
                appearanceSection
                hookInstallSection
                statusSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Master toggle

    private var masterSection: some View {
        Section {
            Toggle(isOn: $enableCodingAgents) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show coding agent sessions in the notch")
                        .font(.body)
                    Text("Discovers Claude Code / Codex / OpenCode / Cursor / Gemini / Kimi sessions on disk and surfaces them in the Agents tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Discovery

    private var discoverySection: some View {
        Section("Discovery") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(Int(pollingInterval)) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $pollingInterval, in: 2...30, step: 1)
                Text("How often Isle re-scans local transcripts. Lower values are more responsive at the cost of marginal CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh now") {
                store.refreshNow()
                feedback = "Refresh triggered"
            }
        }
    }

    // MARK: Appearance & feedback

    private var appearanceSection: some View {
        Section("Appearance & feedback") {
            Toggle("Show indicator in the closed notch when sessions are active", isOn: $showClosedIndicator)
            Toggle("Play a discreet sound when a session needs attention", isOn: $soundEnabled)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Permission expiry display")
                    Spacer()
                    Text("\(Int(permissionTimeoutSeconds)) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $permissionTimeoutSeconds, in: 30...600, step: 30)
                Text("Length of the progress bar shown on each pending permission card. This is a UI hint only — Claude's actual hook timeout is governed by Claude itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Hook installation

    private var hookInstallSection: some View {
        Section {
            ForEach(AgentTool.allCases, id: \.self) { tool in
                AgentInstallRow(tool: tool) { message in
                    feedback = message
                }
            }
        } header: {
            Text("Hooks (M7 — surfaces only)")
        } footer: {
            Text("Installing hooks writes to each agent's own config file (e.g. ~/.claude/settings.json). Use Uninstall to revert. Live event delivery via the IsleHooks CLI starts once the BridgeServer is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Live status

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
                Text("Discovered sessions")
                Spacer()
                Text("\(store.sessions.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.tertiary)
                Text("Recorded decisions")
                Spacer()
                Text("\(store.permissionHistory.count) / \(historyLimit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if store.hasAttentionRequest {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("At least one session needs attention")
                    Spacer()
                }
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Per-agent row

private struct AgentInstallRow: View {
    let tool: AgentTool
    let onFeedback: (String) -> Void

    @State private var isInstalling = false
    @State private var showInstallConsent = false
    @State private var showUninstallConsent = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(isleHex: tool.brandColorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(.body)
                Text(installerStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if installerAvailable {
                Button("Install") {
                    showInstallConsent = true
                }
                .disabled(isInstalling)
                Button("Uninstall") {
                    showUninstallConsent = true
                }
                .disabled(isInstalling)
            } else {
                Text("Coming in M7+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog(
            installConsentTitle,
            isPresented: $showInstallConsent,
            titleVisibility: .visible
        ) {
            Button("Install hooks") { runInstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installConsentMessage)
        }
        .confirmationDialog(
            uninstallConsentTitle,
            isPresented: $showUninstallConsent,
            titleVisibility: .visible
        ) {
            Button("Remove hooks", role: .destructive) { runUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(uninstallConsentMessage)
        }
    }

    // MARK: Consent copy

    private var installConsentTitle: String {
        "Install \(tool.displayName) hooks"
    }

    private var installConsentMessage: String {
        "Isle will modify \(configFilePathDescription).\n\nA timestamped backup of the original will be saved alongside it. You can revert at any time with the Uninstall button."
    }

    private var uninstallConsentTitle: String {
        "Remove \(tool.displayName) hooks"
    }

    private var uninstallConsentMessage: String {
        "Isle will remove its hook entries from \(configFilePathDescription) and restore the file using the latest backup it created during install."
    }

    private var configFilePathDescription: String {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy:
            return "~/.claude/settings.json"
        case .codex:
            return "~/.codex/config.toml"
        case .cursor:
            return "~/.cursor/cli-config.json"
        case .geminiCLI:
            return "~/.gemini/settings.json"
        case .kimiCLI:
            return "~/.kimi/cli-config.json"
        case .openCode:
            return "~/.config/opencode/plugins/"
        }
    }

    private var installerAvailable: Bool {
        // We have installers for Claude / Codex / Cursor / OpenCode / Gemini / Kimi
        // in IsleCore. The discovery is symmetric with the AgentTool cases minus
        // the ones whose installers were not ported in M4-M7.
        switch tool {
        case .claudeCode, .codex, .cursor, .openCode, .geminiCLI, .kimiCLI:
            return true
        case .qoder, .qwenCode, .factory, .codebuddy:
            return false
        }
    }

    private var installerStatusText: String {
        installerAvailable
            ? "Hook installer available"
            : "Installer not yet ported"
    }

    private func runInstall() {
        isInstalling = true
        Task { @MainActor in
            defer { isInstalling = false }
            do {
                let status = try await AgentHookInstallerService.shared.install(tool)
                onFeedback("\(tool.displayName): \(statusLabel(status))")
            } catch {
                onFeedback("\(tool.displayName) install failed — \(error.localizedDescription)")
            }
        }
    }

    private func runUninstall() {
        isInstalling = true
        Task { @MainActor in
            defer { isInstalling = false }
            do {
                _ = try await AgentHookInstallerService.shared.uninstall(tool)
                onFeedback("\(tool.displayName): hooks removed.")
            } catch {
                onFeedback("\(tool.displayName) uninstall failed — \(error.localizedDescription)")
            }
        }
    }

    private func statusLabel(_ status: AgentHookInstallerService.InstallStatus) -> String {
        switch status {
        case .installed:    return "hooks installed."
        case .notInstalled: return "no managed hooks present."
        case .unknown:      return "install request completed (status check unavailable)."
        case let .error(m): return "error — \(m)"
        }
    }
}
