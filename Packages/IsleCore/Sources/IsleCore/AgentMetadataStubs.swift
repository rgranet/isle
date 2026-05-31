//
// Isle — IsleCore
// Copyright (C) 2026 Isle contributors
// GPL v3 — see LICENSE at the repository root.
//
// Per-agent session metadata stubs — file kept intentionally empty.
//
// All five metadata structs (Claude, Codex, Gemini, OpenCode, Cursor)
// referenced by AgentSession.swift now have real implementations alongside
// their respective per-agent backends:
//
//   • ClaudeSessionMetadata    → Claude/ClaudeSessionMetadata.swift  (M2)
//   • CodexSessionMetadata     → Codex/CodexHooks.swift              (M4)
//   • GeminiSessionMetadata    → Gemini/GeminiHooks.swift            (M5b)
//   • OpenCodeSessionMetadata  → OpenCode/OpenCodeHooks.swift        (M5a)
//   • CursorSessionMetadata    → Cursor/CursorHooks.swift            (M5a)
//
// File preserved (not deleted) so the M1/M2 design history stays grep-able
// from this name.

import Foundation
