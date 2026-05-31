//
// Isle — IsleCore tests
// Copyright (C) 2026 Isle contributors
// GPL v3 — see LICENSE at the repository root.
//

import Foundation
import Testing
@testable import IsleCore

@Suite("AgentSession Codable round-trip")
struct AgentSessionCodableTests {
    @Test("Empty session encodes and decodes losslessly")
    func roundTripMinimalSession() throws {
        let original = AgentSession(
            id: "sess-001",
            title: "Hello world",
            tool: .claudeCode,
            phase: .running,
            summary: "Initial",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)
        #expect(decoded == original)
    }

    @Test("Session with metadata, jump target, and permission request round-trips")
    func roundTripFullSession() throws {
        let permission = PermissionRequest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Allow Bash",
            summary: "rm -rf /tmp/foo",
            affectedPath: "/tmp/foo",
            toolName: "Bash",
            toolUseID: "use-42",
            suggestedUpdates: [
                .addRules(
                    destination: .projectSettings,
                    rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "rm /tmp/**")],
                    behavior: .allow
                )
            ]
        )
        let original = AgentSession(
            id: "sess-002",
            title: "Refactor module",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Awaiting your nod",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            firstSeenAt: Date(timeIntervalSince1970: 1_700_000_100),
            permissionRequest: permission,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "isle",
                paneTitle: "main"
            ),
            codexMetadata: CodexSessionMetadata(currentTool: "shell", currentCommandPreview: "git status")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)
        #expect(decoded == original)
    }

    @Test("Decoding tolerates missing optional metadata blocks")
    func decodeMinimalJSON() throws {
        let json = #"""
        {
            "id": "s1",
            "title": "t",
            "tool": "claudeCode",
            "phase": "running",
            "summary": "",
            "updatedAt": 0,
            "firstSeenAt": 0,
            "attachmentState": "stale"
        }
        """#
        let decoded = try JSONDecoder().decode(AgentSession.self, from: Data(json.utf8))
        #expect(decoded.id == "s1")
        #expect(decoded.tool == .claudeCode)
        #expect(decoded.codexMetadata == nil)
    }
}

@Suite("AgentEvent enum Codable")
struct AgentEventCodableTests {
    @Test("SessionStarted event round-trips inside AgentEvent enum")
    func roundTripSessionStarted() throws {
        let event = AgentEvent.sessionStarted(SessionStarted(
            sessionID: "abc",
            title: "Demo",
            tool: .openCode,
            summary: "boot",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test("PermissionRequested event round-trips")
    func roundTripPermissionRequested() throws {
        let event = AgentEvent.permissionRequested(PermissionRequested(
            sessionID: "abc",
            request: PermissionRequest(
                title: "Allow Read",
                summary: "Read /etc/passwd",
                affectedPath: "/etc/passwd"
            ),
            timestamp: Date(timeIntervalSince1970: 1_700_000_700)
        ))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: data)
        #expect(decoded == event)
    }
}

@Suite("ClaudePermissionUpdate Codable")
struct ClaudePermissionUpdateCodableTests {
    @Test("All cases round-trip")
    func roundTripAllCases() throws {
        let cases: [ClaudePermissionUpdate] = [
            .addRules(
                destination: .userSettings,
                rules: [ClaudePermissionRuleValue(toolName: "Read", ruleContent: "/tmp/**")],
                behavior: .allow
            ),
            .setMode(destination: .session, mode: .acceptEdits),
            .addDirectories(destination: .projectSettings, directories: ["/a", "/b"]),
            .removeDirectories(destination: .localSettings, directories: ["/c"]),
        ]
        for original in cases {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ClaudePermissionUpdate.self, from: data)
            #expect(decoded == original)
        }
    }
}

@Suite("TimedCache basics")
struct TimedCacheTests {
    @Test("Compute closure runs once within TTL")
    func computesOnceWithinTTL() {
        let cache = TimedCache<String, Int>(ttl: 60)
        var computeCount = 0
        let first = cache.value(for: "foo") { _ in
            computeCount += 1
            return 42
        }
        let second = cache.value(for: "foo") { _ in
            computeCount += 1
            return 99
        }
        #expect(first == 42)
        #expect(second == 42)
        #expect(computeCount == 1)
    }

    @Test("Distinct keys compute independently")
    func differentKeysComputeIndependently() {
        let cache = TimedCache<String, Int>(ttl: 60)
        let a = cache.value(for: "a") { _ in 1 }
        let b = cache.value(for: "b") { _ in 2 }
        #expect(a == 1)
        #expect(b == 2)
    }
}
