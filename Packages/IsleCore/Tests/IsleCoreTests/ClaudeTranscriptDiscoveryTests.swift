//
// Isle — IsleCore tests
// Copyright (C) 2026 Isle contributors
// GPL v3 — see LICENSE at the repository root.
//

import Foundation
import Testing
@testable import IsleCore

@Suite("ClaudeTranscriptDiscovery")
struct ClaudeTranscriptDiscoveryTests {

    /// Build a temp directory tree shaped like `~/.claude/projects/<encoded>/<session>.jsonl`,
    /// write the given lines into one session file, and return the projects root URL.
    private func makeTranscriptTree(
        sessionID: String = "test-session-001",
        encodedProject: String = "-Users-test-work",
        lines: [String]
    ) throws -> URL {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("isle-claude-discovery-\(UUID().uuidString)", isDirectory: true)
        let projectDir = root.appendingPathComponent(encodedProject, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let sessionFile = projectDir.appendingPathComponent("\(sessionID).jsonl")
        let body = (lines.joined(separator: "\n") + "\n")
        try body.write(to: sessionFile, atomically: true, encoding: .utf8)
        return root
    }

    @Test("Returns empty array when projects root does not exist")
    func emptyWhenMissingRoot() {
        let bogus = URL(fileURLWithPath: "/tmp/isle-no-such-dir-\(UUID().uuidString)")
        let discovery = ClaudeTranscriptDiscovery(rootURL: bogus)
        let sessions = discovery.discoverRecentSessions()
        #expect(sessions.isEmpty)
    }

    @Test("Parses a transcript with cwd, user prompt, and assistant message")
    func parsesBasicSession() throws {
        let lines = [
            #"{"sessionId":"sess-A","cwd":"/Users/test/work","timestamp":"2026-01-15T10:00:00Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"Refactor the parser"},"timestamp":"2026-01-15T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure, starting with X."}],"model":"claude-opus-4-7"},"timestamp":"2026-01-15T10:00:02Z"}"#,
        ]
        let root = try makeTranscriptTree(sessionID: "sess-A", lines: lines)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions()
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "sess-A")
        #expect(session.tool == .claudeCode)
        #expect(session.claudeMetadata?.initialUserPrompt == "Refactor the parser")
        #expect(session.claudeMetadata?.lastUserPrompt == "Refactor the parser")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Sure, starting with X.")
        #expect(session.claudeMetadata?.model == "claude-opus-4-7")
        #expect(session.title == "Claude · work")
        #expect(session.jumpTarget?.workspaceName == "work")
        #expect(session.jumpTarget?.workingDirectory == "/Users/test/work")
    }

    @Test("Tracks tool_use in flight and clears it on matching tool_result")
    func tracksToolUseLifecycle() throws {
        let lines = [
            #"{"sessionId":"sess-B","cwd":"/Users/test/work","timestamp":"2026-01-15T10:00:00Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls -la"}}]},"timestamp":"2026-01-15T10:00:01Z"}"#,
        ]
        let root = try makeTranscriptTree(sessionID: "sess-B", lines: lines)
        defer { try? FileManager.default.removeItem(at: root) }

        let active = try #require(ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions().first)
        #expect(active.claudeMetadata?.currentTool == "Bash")
        #expect(active.claudeMetadata?.currentToolInputPreview?.contains("ls -la") == true)
    }

    @Test("Returns nil when transcript has no cwd")
    func skipsSessionWithoutCwd() throws {
        let lines = [
            #"{"sessionId":"sess-C","timestamp":"2026-01-15T10:00:00Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
        ]
        let root = try makeTranscriptTree(sessionID: "sess-C", lines: lines)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions()
        #expect(sessions.isEmpty)
    }

    @Test("Tolerates malformed JSON lines and keeps parsing")
    func tolerantOfBrokenLines() throws {
        let lines = [
            #"{"sessionId":"sess-D","cwd":"/Users/test/work","timestamp":"2026-01-15T10:00:00Z"}"#,
            "this is not json at all",
            #"{"type":"user","message":{"role":"user","content":"recoverable"}}"#,
        ]
        let root = try makeTranscriptTree(sessionID: "sess-D", lines: lines)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try #require(ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions().first)
        #expect(session.claudeMetadata?.initialUserPrompt == "recoverable")
    }

    @Test("Honors maxAge filter — old files are skipped")
    func skipsOldFiles() throws {
        let lines = [
            #"{"sessionId":"sess-E","cwd":"/Users/test/work","timestamp":"2026-01-15T10:00:00Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"old"}}"#,
        ]
        let root = try makeTranscriptTree(sessionID: "sess-E", lines: lines)
        defer { try? FileManager.default.removeItem(at: root) }

        // Set the file's modification date to 2 days ago.
        let file = root.appendingPathComponent("-Users-test-work/sess-E.jsonl")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -172_800)],
            ofItemAtPath: file.path
        )

        let discovery = ClaudeTranscriptDiscovery(rootURL: root, maxAge: 86_400)
        #expect(discovery.discoverRecentSessions().isEmpty)
    }

    @Test("Subagent jsonl files are ignored")
    func skipsSubagentTranscripts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("isle-claude-subagents-\(UUID().uuidString)", isDirectory: true)
        let subagentDir = root.appendingPathComponent("-Users-test-work/subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: subagentDir, withIntermediateDirectories: true)
        let line = #"{"sessionId":"agent-x","cwd":"/Users/test/work"}"#
        try (line + "\n").write(
            to: subagentDir.appendingPathComponent("agent-x.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions().isEmpty)
    }
}

@Suite("WorkspaceNameResolver")
struct WorkspaceNameResolverTests {
    @Test("Returns last path component for plain cwd")
    func plainPath() {
        #expect(WorkspaceNameResolver.workspaceName(for: "/Users/me/projects/isle") == "isle")
    }

    @Test("Returns project name (not worktree name) when inside a worktree")
    func worktreePath() {
        let cwd = "/Users/me/projects/isle/.git/worktrees/feat-m1/Packages/IsleCore"
        #expect(WorkspaceNameResolver.workspaceName(for: cwd) == "isle")
    }

}

@Suite("ClaudeConfigDirectory")
struct ClaudeConfigDirectoryTests {
    @Test("Defaults to ~/.claude when no override")
    func defaultsToHomeDotClaude() {
        // Clean state — no UserDefaults override
        UserDefaults.standard.removeObject(forKey: ClaudeConfigDirectory.defaultsKey)
        let resolved = ClaudeConfigDirectory.resolved(environment: [:])
        #expect(resolved.path.hasSuffix("/.claude"))
    }

    @Test("Honors CLAUDE_CONFIG_DIR env var when UserDefaults is empty")
    func honorsEnvVar() {
        UserDefaults.standard.removeObject(forKey: ClaudeConfigDirectory.defaultsKey)
        let resolved = ClaudeConfigDirectory.resolved(
            environment: ["CLAUDE_CONFIG_DIR": "/opt/claude-custom"]
        )
        #expect(resolved.path == "/opt/claude-custom")
    }
}
