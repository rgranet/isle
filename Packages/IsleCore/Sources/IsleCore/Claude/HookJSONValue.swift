//
// Isle — derived from open-vibe-island (https://github.com/Octane0411/open-vibe-island)
// Both projects are licensed under the GNU General Public License v3.
// Copyright (C) 2025-2026 open-vibe-island contributors
// Copyright (C) 2026 Isle contributors
//

import Foundation

// Excerpted from CodexHooks.swift (lines 29-75): the generic JSON value type
// used by the Claude/Codex hook payloads. Kept under the original Codex name
// because ClaudeHookJSONValue is a typealias of it.

public enum CodexHookJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: CodexHookJSONValue])
    case array([CodexHookJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: CodexHookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([CodexHookJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
