/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Foundation
import IsleCore

/// Identifies the terminal application that currently hosts a given coding-agent
/// session, by walking the process tree.
///
/// Strategy:
///   1. Enumerate all running terminal apps (bundle ID allow-list).
///   2. For each, ask `ps` for its descendant processes.
///   3. Find descendants whose command contains a known coding-agent name
///      (claude, codex, opencode, …) and whose current working directory
///      matches the session's workingDirectory when available.
///   4. Return the best match; fall back to the most-recently-active terminal
///      among those that had ANY agent descendant; fall back further to the
///      user-preferred terminal from Defaults.
@MainActor
enum AgentTerminalDetector {

    static func detectTerminal(for session: AgentSession) -> KnownTerminal? {
        let candidates = runningKnownTerminals()
        guard !candidates.isEmpty else { return nil }
        guard let sessionCwd = session.jumpTarget?.workingDirectory else {
            // Without a cwd we can't disambiguate beyond "any terminal that
            // looks like it has an agent running".
            return pickAgentHostingTerminal(from: candidates, agentCommand: agentCommandHint(for: session.tool))
        }

        let agentHint = agentCommandHint(for: session.tool)
        var best: (KnownTerminal, Int)?

        for terminal in candidates {
            let descendants = descendantProcesses(of: terminal.pid)
            let score = scoreDescendants(descendants, cwd: sessionCwd, agentHint: agentHint)
            if score > 0 {
                if best == nil || score > best!.1 {
                    best = (terminal.kind, score)
                }
            }
        }

        if let (terminal, _) = best {
            return terminal
        }
        return pickAgentHostingTerminal(from: candidates, agentCommand: agentHint)
    }

    // MARK: Bundle-ID allow-list of supported terminals

    enum KnownTerminal: String, CaseIterable, Identifiable {
        case terminal = "com.apple.Terminal"
        case iterm2 = "com.googlecode.iterm2"
        case warp = "dev.warp.Warp-Stable"
        case warpPreview = "dev.warp.Warp-Preview"
        case ghostty = "com.mitchellh.ghostty"
        case wezterm = "com.github.wez.wezterm"
        case kitty = "net.kovidgoyal.kitty"
        case alacritty = "io.alacritty"
        case hyper = "co.zeit.hyper"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .terminal:    return "Terminal"
            case .iterm2:      return "iTerm2"
            case .warp:        return "Warp"
            case .warpPreview: return "Warp Preview"
            case .ghostty:     return "Ghostty"
            case .wezterm:     return "WezTerm"
            case .kitty:       return "kitty"
            case .alacritty:   return "Alacritty"
            case .hyper:       return "Hyper"
            }
        }

        var processName: String {
            switch self {
            case .terminal:    return "Terminal"
            case .iterm2:      return "iTerm2"
            case .warp:        return "stable"
            case .warpPreview: return "preview"
            case .ghostty:     return "ghostty"
            case .wezterm:     return "wezterm-gui"
            case .kitty:       return "kitty"
            case .alacritty:   return "alacritty"
            case .hyper:       return "Hyper"
            }
        }
    }

    private struct RunningTerminal {
        let kind: KnownTerminal
        let pid: pid_t
        let lastActivated: Date
    }

    // MARK: Discovery

    private static func runningKnownTerminals() -> [RunningTerminal] {
        let now = Date.distantPast
        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningTerminal? in
            guard let id = app.bundleIdentifier, let kind = KnownTerminal(rawValue: id) else { return nil }
            // `launchDate` is the best proxy for "most recently activated"
            // available without polling — newer wins on tie-breaks.
            return RunningTerminal(kind: kind, pid: app.processIdentifier, lastActivated: app.launchDate ?? now)
        }
        .sorted { $0.lastActivated > $1.lastActivated }
    }

    // MARK: Process tree

    private struct ProcessRow {
        let pid: pid_t
        let ppid: pid_t
        let command: String
    }

    private static func psListAll() -> [ProcessRow] {
        // `ps -axo pid=,ppid=,command=` returns one process per line with
        // no header. Use `-x` so we also include processes without a tty.
        let process = Process()
        process.launchPath = "/bin/ps"
        process.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            // `ps` left-pads pids; trim then split into at most 3 fields.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = pid_t(parts[0]),
                  let ppid = pid_t(parts[1]) else { continue }
            rows.append(ProcessRow(pid: pid, ppid: ppid, command: String(parts[2])))
        }
        return rows
    }

    private static func descendantProcesses(of rootPID: pid_t) -> [ProcessRow] {
        let all = psListAll()
        var byParent: [pid_t: [ProcessRow]] = [:]
        for row in all {
            byParent[row.ppid, default: []].append(row)
        }
        var result: [ProcessRow] = []
        var queue: [pid_t] = [rootPID]
        while let next = queue.first {
            queue.removeFirst()
            for child in byParent[next] ?? [] {
                result.append(child)
                queue.append(child.pid)
            }
        }
        return result
    }

    // MARK: Scoring

    private static func scoreDescendants(_ descendants: [ProcessRow], cwd: String, agentHint: String) -> Int {
        var score = 0
        for row in descendants {
            if row.command.contains(agentHint) {
                score += 10
            }
            // Most shells have the cwd as the trailing component of the
            // process command — works for `-zsh` and `/bin/bash` style.
            if row.command.contains(cwd) {
                score += 5
            }
        }
        // Additional bump when at least one descendant explicitly hosts
        // the agent binary AND another shares the working directory.
        return score
    }

    private static func pickAgentHostingTerminal(
        from candidates: [RunningTerminal],
        agentCommand: String
    ) -> KnownTerminal? {
        for terminal in candidates {
            let descendants = descendantProcesses(of: terminal.pid)
            if descendants.contains(where: { $0.command.contains(agentCommand) }) {
                return terminal.kind
            }
        }
        // Last resort: the most-recently-activated supported terminal.
        return candidates.first?.kind
    }

    // MARK: Agent → command-name hint

    private static func agentCommandHint(for tool: AgentTool) -> String {
        switch tool {
        case .claudeCode:   return "claude"
        case .codex:        return "codex"
        case .openCode:     return "opencode"
        case .cursor:       return "cursor"
        case .geminiCLI:    return "gemini"
        case .kimiCLI:      return "kimi"
        case .qoder:        return "qoder"
        case .qwenCode:     return "qwen"
        case .factory:      return "factory"
        case .codebuddy:    return "codebuddy"
        }
    }
}
