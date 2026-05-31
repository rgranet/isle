/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Foundation
import IsleCore

/// One row in the resolved-permissions audit log surfaced under the Agents
/// tab. Lives in-memory only — we deliberately don't persist these to disk
/// because they often include sensitive paths the user wouldn't expect to
/// be archived.
struct PermissionHistoryEntry: Identifiable, Equatable, Sendable {
    enum Decision: String, Equatable, Sendable {
        case allowed
        case allowedWithRule
        case denied
        case unknown

        var displayLabel: String {
            switch self {
            case .allowed:         return "Allowed"
            case .allowedWithRule: return "Allowed + rule"
            case .denied:          return "Denied"
            case .unknown:         return "Resolved"
            }
        }

        var systemSymbol: String {
            switch self {
            case .allowed:         return "checkmark.circle.fill"
            case .allowedWithRule: return "checkmark.shield.fill"
            case .denied:          return "xmark.circle.fill"
            case .unknown:         return "circle.dashed"
            }
        }
    }

    let id: UUID
    let sessionID: String
    let tool: AgentTool
    let toolName: String?
    let title: String
    let affectedPath: String
    let workspace: String?
    let resolvedAt: Date
    /// How long the request was on screen before being resolved.
    let elapsedSeconds: TimeInterval
    let decision: Decision

    var elapsedShortLabel: String {
        if elapsedSeconds < 60 {
            return "\(Int(elapsedSeconds))s"
        }
        let minutes = Int(elapsedSeconds / 60)
        return "\(minutes)m"
    }
}
