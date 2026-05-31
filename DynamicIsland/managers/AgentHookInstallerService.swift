/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Foundation
import IsleCore

/// Unified façade in front of the per-agent installation managers shipped
/// inside IsleCore.
///
/// Each `AgentTool` case is routed to the appropriate IsleCore manager and
/// fed the IsleHooks binary URL discovered via `HooksBinaryLocator`. Errors
/// are surfaced as `InstallerError` so the UI layer can render a friendly
/// message.
///
/// M7.6 scope:
///   • install / uninstall / status are wired for hook-based agents
///     (Claude, Codex, Cursor, Gemini, Kimi)
///   • OpenCode uses a JavaScript plugin (not a binary hook) — its install
///     path needs the plugin source bundled at Resources/Plugins/OpenCode/
///     which we'll add in M9 packaging. Surfaced as `.pluginSourceMissing`
///     for now.
@MainActor
final class AgentHookInstallerService {
    static let shared = AgentHookInstallerService()

    enum InstallStatus: Equatable {
        case installed
        case notInstalled
        case unknown
        case error(String)
    }

    enum InstallerError: Error, LocalizedError {
        case hooksBinaryNotFound
        case pluginSourceMissing
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .hooksBinaryNotFound:
                return "Isle Hooks binary not found. Build it once with `swift build -c release --package-path Packages/IsleCore`."
            case .pluginSourceMissing:
                return "OpenCode plugin bundle not yet shipped with Isle. Coming in M9."
            case let .underlying(message):
                return message
            }
        }
    }

    private init() {}

    // MARK: Public API

    /// Discovers the IsleHooks binary on disk. Returns nil when not present.
    func hooksBinaryURL() -> URL? {
        let bundleHelpers = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers", isDirectory: true)
        // Also fall back to the IsleCore SwiftPM `.build/release/` location for
        // development runs.
        let pkgURL = URL(fileURLWithPath: "Packages/IsleCore", isDirectory: true,
                         relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        return HooksBinaryLocator.locate(
            currentDirectory: pkgURL,
            executableDirectory: bundleHelpers
        )
    }

    func install(_ tool: AgentTool) async throws -> InstallStatus {
        guard let binary = hooksBinaryURL() else {
            throw InstallerError.hooksBinaryNotFound
        }
        return try await Task.detached { [self] in
            try await runInstall(tool: tool, hooksBinary: binary)
        }.value
    }

    func uninstall(_ tool: AgentTool) async throws -> InstallStatus {
        return try await Task.detached { [self] in
            try await runUninstall(tool: tool)
        }.value
    }

    func status(_ tool: AgentTool) async -> InstallStatus {
        return await Task.detached { [self] in
            await fetchStatus(tool: tool)
        }.value
    }

    // MARK: Per-agent routing

    nonisolated private func runInstall(tool: AgentTool, hooksBinary: URL) async throws -> InstallStatus {
        do {
            switch tool {
            case .claudeCode:
                let s = try ClaudeHookInstallationManager(hookSource: "claude").install(hooksBinaryURL: hooksBinary)
                return s.hasClaudeIslandHooks ? .installed : .notInstalled
            case .qoder:
                let s = try ClaudeHookInstallationManager(hookSource: "qoder").install(hooksBinaryURL: hooksBinary)
                return s.hasClaudeIslandHooks ? .installed : .notInstalled
            case .qwenCode:
                let s = try ClaudeHookInstallationManager(hookSource: "qwen").install(hooksBinaryURL: hooksBinary)
                return s.hasClaudeIslandHooks ? .installed : .notInstalled
            case .factory:
                let s = try ClaudeHookInstallationManager(hookSource: "factory").install(hooksBinaryURL: hooksBinary)
                return s.hasClaudeIslandHooks ? .installed : .notInstalled
            case .codebuddy:
                let s = try ClaudeHookInstallationManager(hookSource: "codebuddy").install(hooksBinaryURL: hooksBinary)
                return s.hasClaudeIslandHooks ? .installed : .notInstalled
            case .codex:
                _ = try CodexHookInstallationManager().install(hooksBinaryURL: hooksBinary)
                return .installed
            case .cursor:
                _ = try CursorHookInstallationManager().install(hooksBinaryURL: hooksBinary)
                return .installed
            case .geminiCLI:
                _ = try GeminiHookInstallationManager().install(hooksBinaryURL: hooksBinary)
                return .installed
            case .kimiCLI:
                _ = try KimiHookInstallationManager().install(hooksBinaryURL: hooksBinary)
                return .installed
            case .openCode:
                guard let pluginURL = Bundle.main.url(forResource: "opencode-plugin", withExtension: "js") else {
                    throw InstallerError.pluginSourceMissing
                }
                let pluginData = try Data(contentsOf: pluginURL)
                _ = try OpenCodePluginInstallationManager().install(pluginSourceData: pluginData)
                return .installed
            }
        } catch let err as InstallerError {
            throw err
        } catch {
            throw InstallerError.underlying("\(error)")
        }
    }

    nonisolated private func runUninstall(tool: AgentTool) async throws -> InstallStatus {
        do {
            switch tool {
            case .claudeCode:
                _ = try ClaudeHookInstallationManager(hookSource: "claude").uninstall()
            case .qoder:
                _ = try ClaudeHookInstallationManager(hookSource: "qoder").uninstall()
            case .qwenCode:
                _ = try ClaudeHookInstallationManager(hookSource: "qwen").uninstall()
            case .factory:
                _ = try ClaudeHookInstallationManager(hookSource: "factory").uninstall()
            case .codebuddy:
                _ = try ClaudeHookInstallationManager(hookSource: "codebuddy").uninstall()
            case .codex:
                _ = try CodexHookInstallationManager().uninstall()
            case .cursor:
                _ = try CursorHookInstallationManager().uninstall()
            case .geminiCLI:
                _ = try GeminiHookInstallationManager().uninstall()
            case .kimiCLI:
                _ = try KimiHookInstallationManager().uninstall()
            case .openCode:
                _ = try OpenCodePluginInstallationManager().uninstall()
            }
            return .notInstalled
        } catch let err as InstallerError {
            throw err
        } catch {
            throw InstallerError.underlying("\(error)")
        }
    }

    nonisolated private func fetchStatus(tool: AgentTool) async -> InstallStatus {
        do {
            switch tool {
            case .claudeCode:
                return try ClaudeHookInstallationManager(hookSource: "claude").status().hasClaudeIslandHooks ? .installed : .notInstalled
            case .qoder:
                return try ClaudeHookInstallationManager(hookSource: "qoder").status().hasClaudeIslandHooks ? .installed : .notInstalled
            case .qwenCode:
                return try ClaudeHookInstallationManager(hookSource: "qwen").status().hasClaudeIslandHooks ? .installed : .notInstalled
            case .factory:
                return try ClaudeHookInstallationManager(hookSource: "factory").status().hasClaudeIslandHooks ? .installed : .notInstalled
            case .codebuddy:
                return try ClaudeHookInstallationManager(hookSource: "codebuddy").status().hasClaudeIslandHooks ? .installed : .notInstalled
            case .codex:
                _ = try CodexHookInstallationManager().status()
                return .unknown
            case .cursor:
                _ = try CursorHookInstallationManager().status()
                return .unknown
            case .geminiCLI:
                _ = try GeminiHookInstallationManager().status()
                return .unknown
            case .kimiCLI:
                _ = try KimiHookInstallationManager().status()
                return .unknown
            case .openCode:
                let status = try OpenCodePluginInstallationManager().status()
                return status.isInstalled ? .installed : .notInstalled
            }
        } catch {
            return .error("\(error)")
        }
    }
}
