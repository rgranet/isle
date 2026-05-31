/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version. See LICENSE at the repository root.
 */

import Combine
import Defaults
import Foundation
import IsleCore

/// Periodically scans local coding-agent transcripts and exposes the discovered
/// sessions to SwiftUI.
///
/// In M3 only Claude Code is implemented (via `ClaudeTranscriptDiscovery`).
/// Codex (M4), OpenCode (M5), and friends will plug additional sources into
/// `refreshSessions()` in their respective milestones.
@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    /// All recently-active sessions, sorted by `updatedAt` descending.
    @Published private(set) var sessions: [AgentSession] = [] {
        didSet {
            reconcilePermissionTracking(previous: oldValue, current: sessions)
            handleAttentionTransition(previous: oldValue, current: sessions)
        }
    }

    /// Resolved-permission audit log surfaced in the Agents tab. Most-recent
    /// entries first, capped at `Defaults[.codingAgentsHistoryLimit]`.
    @Published private(set) var permissionHistory: [PermissionHistoryEntry] = []

    /// Map of `session.id → permission appearance timestamp`. Drives the
    /// per-card expiry progress bar so the user knows how long they have
    /// before Claude times out and falls through to its default policy.
    @Published private(set) var permissionStartTimes: [String: Date] = [:]

    /// Tracks the previous "needs attention" boolean so we only flip the
    /// notch over to the Agents tab on a rising edge (not every refresh).
    private var previousHasAttention = false

    /// Detects sessions whose `permissionRequest` just appeared or just
    /// disappeared so we can: (a) timestamp newly-appeared requests for the
    /// progress bar, (b) move resolved requests into `permissionHistory`,
    /// (c) trigger the audio cue.
    private func reconcilePermissionTracking(previous: [AgentSession], current: [AgentSession]) {
        let prevByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })

        // Newly-appeared permission requests.
        for session in current where session.permissionRequest != nil {
            let hadBefore = prevByID[session.id]?.permissionRequest != nil
            if !hadBefore {
                permissionStartTimes[session.id] = .now
                AgentPermissionSoundPlayer.shared.playAttentionCue()
                // v1.2 — briefly grow the notch like the volume HUD so the
                // arrival is impossible to miss. The compact attention
                // indicator stays after the expansion auto-collapses.
                if Defaults[.codingAgentsGrowNotchOnArrival] {
                    DynamicIslandViewCoordinator.shared.toggleExpandingView(
                        status: true,
                        type: .codingAgentArrived(
                            brandColorHex: session.tool.brandColorHex,
                            title: session.permissionRequest?.title ?? session.tool.displayName
                        ),
                        autoHideDuration: 3.0
                    )
                }
            }
        }

        // Disappeared permission requests (either resolved or session ended).
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for prevSession in previous {
            guard let oldRequest = prevSession.permissionRequest else { continue }
            let stillPending = currentByID[prevSession.id]?.permissionRequest != nil
            if !stillPending {
                let startedAt = permissionStartTimes.removeValue(forKey: prevSession.id) ?? .now
                appendHistory(
                    PermissionHistoryEntry(
                        id: UUID(),
                        sessionID: prevSession.id,
                        tool: prevSession.tool,
                        toolName: oldRequest.toolName,
                        title: oldRequest.title,
                        affectedPath: oldRequest.affectedPath,
                        workspace: prevSession.jumpTarget?.workspaceName,
                        resolvedAt: .now,
                        elapsedSeconds: Date.now.timeIntervalSince(startedAt),
                        decision: pendingDecisions.removeValue(forKey: prevSession.id) ?? .unknown
                    )
                )
            }
        }
    }

    private func appendHistory(_ entry: PermissionHistoryEntry) {
        let limit = max(1, Defaults[.codingAgentsHistoryLimit])
        var updated = permissionHistory
        updated.insert(entry, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        permissionHistory = updated
    }

    /// Side-channel for recording the *user's* decision before the session
    /// state update lands. The inline Allow / Deny buttons call this
    /// just before forwarding to BridgeServer so we can label the history
    /// entry with the right verdict. Cleared in `reconcilePermissionTracking`.
    private var pendingDecisions: [String: PermissionHistoryEntry.Decision] = [:]

    func recordUserDecision(_ decision: PermissionHistoryEntry.Decision, for sessionID: String) {
        pendingDecisions[sessionID] = decision
    }

    /// Send the notch to the Agents tab the first time any session enters
    /// an attention-required phase. Avoids surprising the user when nothing
    /// changed and avoids overriding the tab they manually navigated to.
    private func handleAttentionTransition(previous: [AgentSession], current: [AgentSession]) {
        let nowNeedsAttention = current.contains { $0.phase.requiresAttention }
        defer { previousHasAttention = nowNeedsAttention }
        guard nowNeedsAttention, !previousHasAttention else { return }

        // Switch to the Agents tab so when the user hovers the notch (or
        // if it's already open) the highlighted session with its inline
        // Allow / Deny buttons is the first thing they see.
        DynamicIslandViewCoordinator.shared.currentView = .codingAgents
    }

    /// `true` when at least one session needs user attention (permission /
    /// answer pending). Drives the closed-notch attention indicator. In M3
    /// this is always false because phases come from post-hoc transcripts,
    /// not from live hooks; M5 will flip this on real `PermissionRequested`.
    var hasAttentionRequest: Bool {
        sessions.contains { $0.phase.requiresAttention }
    }

    /// Returns a deduplicated list of brand-color hexes from currently
    /// active sessions, capped at `max` entries, ordered by recency.
    func brandColors(limit max: Int = 3) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions {
            let hex = session.tool.brandColorHex
            if seen.insert(hex).inserted {
                result.append(hex)
                if result.count >= max { break }
            }
        }
        return result
    }

    private let claudeDiscovery: ClaudeTranscriptDiscovery
    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init(claudeDiscovery: ClaudeTranscriptDiscovery = ClaudeTranscriptDiscovery()) {
        self.claudeDiscovery = claudeDiscovery

        Defaults.publisher(.enableCodingAgents)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleEnabledChange(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.codingAgentsPollingInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restartPollingIfNeeded()
            }
            .store(in: &cancellables)

        if Defaults[.enableCodingAgents] {
            startPolling()
        }
    }

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            startPolling()
        } else {
            stopPolling()
            sessions = []
            permissionStartTimes.removeAll()
            pendingDecisions.removeAll()
        }
    }

    private func restartPollingIfNeeded() {
        guard Defaults[.enableCodingAgents] else { return }
        stopPolling()
        startPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let interval = max(1.0, Defaults[.codingAgentsPollingInterval])
        pollTask = Task { [weak self] in
            await self?.refreshSessions()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.refreshSessions()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Public refresh hook — useful for "pull-to-refresh" gestures and for
    /// triggering an immediate scan after the notch opens.
    func refreshNow() {
        Task { await refreshSessions() }
    }

    /// M7.8 — apply a live snapshot pushed by the BridgeServer whenever
    /// the local session state changes (hook event OR user-driven resolve).
    ///
    /// Replaces hook-managed sessions while preserving discovery-only
    /// (post-hoc transcript) sessions the bridge wouldn't know about.
    func applyLiveSnapshot(_ liveSessions: [AgentSession]) {
        let liveIDs = Set(liveSessions.map(\.id))
        let discoveryOnly = sessions.filter { !liveIDs.contains($0.id) && !$0.isHookManaged }
        let merged = (liveSessions + discoveryOnly).sorted { $0.updatedAt > $1.updatedAt }

        if merged != sessions {
            sessions = merged
        }

        print("📡 [Isle] applyLiveSnapshot → \(merged.count) sessions, attention=\(merged.contains { $0.phase.requiresAttention })")
    }


    private func refreshSessions() async {
        // Disk-read + process-scan in parallel on a background actor so the
        // main thread never blocks on `ps`/`lsof`.
        async let discoveredFuture: [AgentSession] = Task.detached { [discovery = claudeDiscovery] in
            discovery.discoverRecentSessions()
        }.value
        async let liveProcessesFuture: [ActiveAgentProcessDiscovery.ProcessSnapshot] = Task.detached {
            ActiveAgentProcessDiscovery().discover()
        }.value

        let discovered = await discoveredFuture
        let liveProcesses = await liveProcessesFuture

        // Build keyed lookups so we can not only mark sessions alive but
        // also enrich them with the terminal-app name the live process
        // discovery resolved (Warp / iTerm / Terminal.app / Ghostty / …).
        // Transcript path is the most precise key; workingDirectory is
        // the broader fallback.
        let byTranscriptPath = Dictionary(grouping: liveProcesses, by: { $0.transcriptPath ?? "" })
            .compactMapValues { $0.first }
        let byWorkingDir = Dictionary(grouping: liveProcesses, by: { $0.workingDirectory ?? "" })
            .compactMapValues { $0.first }

        let enriched = discovered.map { session -> AgentSession in
            var s = session
            var matchedSnapshot: ActiveAgentProcessDiscovery.ProcessSnapshot?
            if let transcriptPath = s.claudeMetadata?.transcriptPath,
               let snap = byTranscriptPath[transcriptPath] {
                matchedSnapshot = snap
            } else if let workdir = s.jumpTarget?.workingDirectory,
                      let snap = byWorkingDir[workdir] {
                matchedSnapshot = snap
            }

            if let snap = matchedSnapshot {
                s.isProcessAlive = true
                // Propagate the resolved terminal-app name into the
                // session's jumpTarget so the UI can show a "Warp" /
                // "iTerm" badge next to the title (mirrors what the
                // upstream open-vibe-island app does).
                if let terminalApp = snap.terminalApp, !terminalApp.isEmpty {
                    var jt = s.jumpTarget ?? JumpTarget(
                        terminalApp: terminalApp,
                        workspaceName: "",
                        paneTitle: ""
                    )
                    jt.terminalApp = terminalApp
                    if let tty = snap.terminalTTY { jt.terminalTTY = tty }
                    s.jumpTarget = jt
                }
            }
            return s
        }

        // M7.8 — do NOT clobber hook-managed live sessions with the
        // freshly-discovered post-hoc transcript versions.
        let liveHookIDs = Set(sessions.filter(\.isHookManaged).map(\.id))
        let discoveryOnly = enriched.filter { !liveHookIDs.contains($0.id) }
        let liveHookSessions = sessions.filter { liveHookIDs.contains($0.id) }
        let merged = (liveHookSessions + discoveryOnly).sorted { $0.updatedAt > $1.updatedAt }

        let aliveCount = merged.filter { $0.isProcessAlive }.count
        print("📡 [Isle] refreshSessions: discovery=\(discovered.count), procs=\(liveProcesses.count), alive=\(aliveCount), hook-live=\(liveHookSessions.count), total=\(merged.count)")

        if merged != sessions {
            sessions = merged
        }
    }
}
