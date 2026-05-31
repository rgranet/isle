/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Foundation
import IsleCore

/// Singleton that owns the lifetime of the in-app IPC `BridgeServer`.
///
/// **M7.7 scope**: start a Unix-socket listener on `BridgeSocketLocation.defaultURL`
/// at app launch so the IsleHooks CLI processes spawned by user-installed
/// agent hooks have a socket to connect to. The server receives events
/// and updates its internal `SessionState`, but **we do not yet propagate
/// those events out to the SwiftUI layer** — that's M7.8.
///
/// In the meantime, `AgentSessionStore` continues to discover sessions by
/// polling local transcripts every 5 s (M2 behaviour), which is "live
/// enough" for most flows. M7.8 will wire BridgeServer's session events
/// directly into the store so permissions and tool calls show up instantly.
@MainActor
final class AgentHookBridgeManager {
    static let shared = AgentHookBridgeManager()

    private var server: BridgeServer?
    private(set) var isRunning: Bool = false
    private(set) var lastError: String?

    var socketPath: String { BridgeSocketLocation.defaultURL.path }

    private init() {}

    func startIfNeeded() {
        guard server == nil else { return }
        let s = BridgeServer(socketURL: BridgeSocketLocation.defaultURL)

        // M7.8 — wire live agent events back into the SwiftUI store.
        // The callback fires on BridgeServer's internal queue; we hop to
        // the main actor before mutating the @Published store.
        s.onSessionsChanged = { sessions in
            Task { @MainActor in
                AgentSessionStore.shared.applyLiveSnapshot(sessions)
            }
        }

        do {
            try s.start()
            server = s
            isRunning = true
            lastError = nil
            print("📡 [Isle] BridgeServer listening on \(socketPath)")
        } catch {
            lastError = "\(error)"
            print("⚠️ [Isle] BridgeServer failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    /// Forward a user's Allow / Deny decision back to the BridgeServer so
    /// the waiting hook process can resume.
    func resolvePermission(sessionID: String, resolution: PermissionResolution) {
        server?.resolvePermission(sessionID: sessionID, resolution: resolution)
    }
}
