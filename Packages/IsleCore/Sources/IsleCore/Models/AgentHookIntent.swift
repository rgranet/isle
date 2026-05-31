//
// Isle — derived from open-vibe-island (https://github.com/Octane0411/open-vibe-island)
// Both projects are licensed under the GNU General Public License v3.
// Copyright (C) 2025-2026 open-vibe-island contributors
// Copyright (C) 2026 Isle contributors
//
import Foundation

/// Tri-state record of whether the user wants a given agent's hooks installed.
///
/// `untouched` is the default for a never-seen agent. Once the user makes a
/// decision — in onboarding or settings — the value becomes either
/// `installed` or `uninstalled`. The startup flow must honour `uninstalled`
/// and never silently reinstall.
public enum AgentHookIntent: String, Codable, Sendable, CaseIterable {
    case untouched
    case installed
    case uninstalled
}

/// Canonical identifier for every agent whose hooks Isle manages.
///
/// Raw values are stable on-disk keys (used in UserDefaults); do not rename
/// existing cases without a migration.
public enum AgentIdentifier: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case cursor
    case qoder
    case qwenCode
    case factory
    case codebuddy
    case openCode
    case gemini
    case kimi
    case claudeUsageBridge
}
