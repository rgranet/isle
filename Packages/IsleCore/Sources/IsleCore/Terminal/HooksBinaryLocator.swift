//
// Isle — derived from open-vibe-island (https://github.com/Octane0411/open-vibe-island)
// Both projects are licensed under the GNU General Public License v3.
// Copyright (C) 2025-2026 open-vibe-island contributors
// Copyright (C) 2026 Isle contributors
//

import Foundation

public enum ManagedHooksBinary {
    // Isle-native names (current).
    public static let binaryName = "IsleHooks"
    // Upstream open-vibe-island name kept for first-launch migration from
    // an existing OpenIsland install on the user's machine.
    public static let openIslandLegacyBinaryName = "OpenIslandHooks"
    public static let vibeIslandLegacyBinaryName = "VibeIslandHooks"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        installDirectory(fileManager: fileManager)
            .appendingPathComponent(binaryName)
            .standardizedFileURL
    }

    public static func candidateURLs(fileManager: FileManager = .default) -> [URL] {
        [
            defaultURL(fileManager: fileManager),
            openIslandLegacyInstallDirectory(fileManager: fileManager)
                .appendingPathComponent(openIslandLegacyBinaryName)
                .standardizedFileURL,
            vibeIslandLegacyInstallDirectory(fileManager: fileManager)
                .appendingPathComponent(vibeIslandLegacyBinaryName)
                .standardizedFileURL,
        ]
    }

    @discardableResult
    public static func install(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let resolvedSourceURL = sourceURL.standardizedFileURL
        let resolvedDestinationURL = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL

        try fileManager.createDirectory(
            at: resolvedDestinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if resolvedSourceURL != resolvedDestinationURL {
            if fileManager.fileExists(atPath: resolvedDestinationURL.path) {
                try fileManager.removeItem(at: resolvedDestinationURL)
            }
            try fileManager.copyItem(at: resolvedSourceURL, to: resolvedDestinationURL)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolvedDestinationURL.path)
        return resolvedDestinationURL
    }

    /// Overwrites the installed hooks binary if the bundle source differs.
    /// Returns `true` if the binary was updated.
    @discardableResult
    public static func updateIfNeeded(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let installedURL = defaultURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: installedURL.path) else {
            return false
        }

        let sourceData = try Data(contentsOf: sourceURL)
        let installedData = try Data(contentsOf: installedURL)
        guard sourceData != installedData else {
            return false
        }

        try fileManager.removeItem(at: installedURL)
        try fileManager.copyItem(at: sourceURL, to: installedURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
        return true
    }

    private static func installDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Isle", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func openIslandLegacyInstallDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func vibeIslandLegacyInstallDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VibeIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }
}

public enum HooksBinaryLocator {
    public static func locate(
        fileManager: FileManager = .default,
        currentDirectory: URL? = nil,
        executableDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicitPath = environment["ISLE_HOOKS_BINARY"]
            ?? environment["OPEN_ISLAND_HOOKS_BINARY"]
            ?? environment["VIBE_ISLAND_HOOKS_BINARY"],
           fileManager.isExecutableFile(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath).standardizedFileURL
        }

        let currentDirectory = currentDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates = [
            // Isle-native lookup order.
            executableDirectory?.appendingPathComponent("IsleHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("IsleHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/IsleHooks"),
            // Backwards-compat with open-vibe-island installs already on disk.
            executableDirectory?.appendingPathComponent("OpenIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("OpenIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/OpenIslandHooks"),
            executableDirectory?.appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/VibeIslandHooks"),
        ].compactMap { $0 } + ManagedHooksBinary.candidateURLs(fileManager: fileManager) + {
            #if arch(arm64)
            let archTriple = "arm64-apple-macosx"
            #elseif arch(x86_64)
            let archTriple = "x86_64-apple-macosx"
            #else
            let archTriple = "unknown-apple-macosx"
            #endif
            return [
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/IsleHooks"),
                currentDirectory.appendingPathComponent(".build/release/IsleHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/IsleHooks"),
                currentDirectory.appendingPathComponent(".build/debug/IsleHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/release/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/debug/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/debug/VibeIslandHooks"),
            ]
        }()

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.standardizedFileURL
        }

        return nil
    }
}
