/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Foundation
import IsleCore

/// Routes a tap on an agent session card to the terminal that actually
/// hosts that session.
///
/// Strategy (M6.5 — improved over M6-light):
///   1. Walk the process tree (`AgentTerminalDetector`) to find the
///      terminal app whose process subtree contains the agent's runtime
///      (claude / codex / opencode / …) and ideally has a descendant in
///      the session's `workingDirectory`.
///   2. Focus that specific terminal using its native activation path
///      (AppleScript activate / URL scheme / NSRunningApplication.activate).
///   3. If detection finds nothing, fall back to the user-preferred
///      terminal from Defaults — defaulting to `.system` which uses
///      `open -a Terminal <path>` (creates a new tab/window at the path).
///
/// Limitations still:
///   - We focus the *application*, not the exact tab/window where the
///     session is running. To focus the precise pane we'd need per-terminal
///     SQLite/Accessibility integrations (Warp pane UUIDs, iTerm2 window
///     ids, etc.) — the WarpSQLiteReader port in IsleCore is the start of
///     that; full per-pane routing is M6.7.
enum AgentSessionJumpback {

    @MainActor
    static func open(_ session: AgentSession) {
        guard let directory = session.jumpTarget?.workingDirectory,
              !directory.isEmpty else {
            return
        }

        // 1) Prefer the terminal that actually hosts this session.
        if let detected = AgentTerminalDetector.detectTerminal(for: session) {
            if focus(detected, fallbackPath: directory) {
                return
            }
        }

        // 2) Fall back to the user-preferred terminal (Defaults).
        // For now this lookup is implicit via NSWorkspace's `open -a`
        // chain. M9.x will add an explicit Defaults key for the user.
        if openInTerminalApp(path: directory) {
            return
        }

        // 3) Finder as ultimate fallback.
        openInFinder(path: directory)
    }

    // MARK: Per-terminal focus

    @MainActor
    private static func focus(_ terminal: AgentTerminalDetector.KnownTerminal, fallbackPath: String) -> Bool {
        if let runningApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == terminal.rawValue }) {
            // Activate the existing running instance — this brings its
            // last-focused window forward without spawning a new tab.
            return runningApp.activate(options: [.activateIgnoringOtherApps])
        }

        // App not running (rare since we found it in the detector, but
        // possible if it quit between detection and focus). Re-launch
        // with the session's cwd as the open argument.
        switch terminal {
        case .terminal:    return openInTerminalApp(path: fallbackPath)
        case .iterm2:      return openInITerm2(path: fallbackPath)
        case .warp, .warpPreview: return openInWarp(path: fallbackPath)
        case .ghostty:     return openInGhostty(path: fallbackPath)
        case .wezterm:     return openInWezTerm(path: fallbackPath)
        case .kitty, .alacritty, .hyper:
            return openInBundle(terminal.rawValue, path: fallbackPath)
        }
    }

    // MARK: Per-terminal launchers (used when the app isn't running)

    private static func openInTerminalApp(path: String) -> Bool {
        runOpen(["-a", "Terminal", path])
    }

    private static func openInITerm2(path: String) -> Bool {
        // If iTerm2 is closed, `open -a iTerm` will spawn it at the cwd.
        runOpen(["-a", "iTerm", path])
    }

    private static func openInWarp(path: String) -> Bool {
        // Warp URL scheme: only works to open a NEW tab. Used only as a
        // re-launch fallback — when Warp is already running, we activate
        // its NSRunningApplication instance instead (see focus()).
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "warp://action/new_tab?path=\(encoded)") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    private static func openInGhostty(path: String) -> Bool {
        runOpen(["-na", "Ghostty", "--args", "--working-directory=\(path)"])
    }

    private static func openInWezTerm(path: String) -> Bool {
        runOpen(["-na", "WezTerm", "--args", "start", "--cwd", path])
    }

    private static func openInBundle(_ bundleID: String, path: String) -> Bool {
        runOpen(["-b", bundleID, path])
    }

    private static func openInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path),
        ])
    }

    // MARK: Helpers

    @discardableResult
    private static func runOpen(_ arguments: [String]) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/open"
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
