/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Combine
import IsleCore
import SwiftUI

/// Auto-presents an Isle permission sheet in a floating window whenever
/// an agent session needs user approval.
///
/// The window sits above all other apps (`.statusBar` window level), is
/// shown without animation, and stays visible until the user clicks
/// Allow or Deny. Decision is forwarded to `AgentHookBridgeManager` which
/// pushes it back to the BridgeServer; the waiting hook process unblocks
/// and the indicator clears on its own.
@MainActor
final class AgentPermissionPresenter: ObservableObject {
    static let shared = AgentPermissionPresenter()

    private var window: NSWindow?
    private var currentSessionID: String?
    private var observation: AnyCancellable?

    private init() {}

    /// Start observing AgentSessionStore. Called once at app launch.
    func start() {
        observation = AgentSessionStore.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.reactToSessions(sessions)
            }
    }

    // MARK: Reaction loop

    private func reactToSessions(_ sessions: [AgentSession]) {
        // Find the first session that is waiting for the user.
        let pending = sessions.first { $0.phase.requiresAttention && $0.permissionRequest != nil }

        if let pending, let request = pending.permissionRequest {
            // Already presenting the same session's request? Don't churn.
            if currentSessionID == pending.id, window?.isVisible == true {
                return
            }
            present(request: request, sessionID: pending.id, tool: pending.tool)
        } else {
            // No more pending requests — dismiss any open sheet.
            dismiss()
        }
    }

    // MARK: Window mgmt

    private func present(request: PermissionRequest, sessionID: String, tool: AgentTool) {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }

        let host = NSHostingController(
            rootView: AgentPermissionSheet(request: request) { [weak self] resolution in
                self?.handleDecision(resolution, sessionID: sessionID)
            }
            .background(VisualEffectBackground())
            .frame(width: 460)
        )
        window.contentViewController = host

        window.setContentSize(NSSize(width: 460, height: 280))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        currentSessionID = sessionID
    }

    private func dismiss() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        currentSessionID = nil
    }

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        self.window = w
    }

    private func handleDecision(_ resolution: PermissionResolution, sessionID: String) {
        AgentHookBridgeManager.shared.resolvePermission(
            sessionID: sessionID,
            resolution: resolution
        )
        dismiss()
    }
}

/// Tiny wrapper so SwiftUI views inside an NSHostingController pick up
/// a translucent macOS background instead of an opaque white card.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
