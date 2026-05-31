# Contributing to Isle

Thanks for considering a contribution. Isle is GPL v3 and welcomes patches,
bug reports, and new agent integrations.

## Local development

You need:

- **macOS 14.0** (Sonoma) or later — 15+ recommended for testing newer APIs.
- **Xcode 16+** with the Swift 6 toolchain.
- A MacBook with a notch for full-fidelity UI testing (the app still runs
  on non-notched Macs, but some layouts only make sense around the notch).
- *(Optional)* `brew install git-lfs` if you plan to add binary assets
  larger than a few hundred kilobytes (logos, animation sources, etc.).

Clone and open:

```bash
git clone https://github.com/withmii/isle.git
cd isle
open DynamicIsland.xcodeproj
```

Build the support binaries (only needed if you touch `Packages/IsleCore`):

```bash
swift build --package-path Packages/IsleCore
swift test  --package-path Packages/IsleCore
```

## Project layout

```
DynamicIsland/           — main SwiftUI app target (com.withmii.isle)
DynamicIsland.xcodeproj/ — Xcode project
Packages/
  IsleCore/              — Swift package: event schema + two CLI products
    Sources/
      IsleCore/          — shared library (Sendable, Codable event model)
      IsleHooks/         — per-agent hook adapter binary
      IsleSetup/         — install / uninstall CLI for agent hooks
    Tests/
.vendor/                 — vendored source from upstreams (Atoll,
                            open-vibe-island). Treat as read-only;
                            re-vendor with the script in `scripts/`.
docs/                    — user + architecture docs
```

## Coding conventions

- **Swift 6 ready** — new code should compile under strict concurrency
  with no warnings. Prefer `Sendable` types, mark `@MainActor` deliberately.
- Prefer `Codable` for any data crossing a process boundary (the agent
  hooks talk to the app via JSON).
- Use `swift-format` defaults (4-space indent, 100-col soft limit).
- Every new source file must carry the **GPL v3 preamble** at the top.
  Copy it from any existing file in `Packages/IsleCore/Sources/IsleCore/`.
- Public API: doc-comment it. Internal helpers: a one-liner is fine.
- No new third-party dependencies without discussion — Isle's footprint
  is a feature.

## Pull request process

1. Branch from `main`: `git switch -c feat/your-thing`.
2. Make focused commits with clear messages.
3. Before opening the PR, run:
   ```bash
   swift test --package-path Packages/IsleCore
   xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
     -destination 'platform=macOS' build
   ```
4. Open the PR against `main`. Include screenshots / screen recordings
   for any UI change.
5. A maintainer will review. CI must be green. Squash on merge is the
   default.

## Reporting issues

File issues at <https://github.com/withmii/isle/issues>. Useful info:

- macOS version and Mac model (`sysctl hw.model`).
- Isle version (Settings → About).
- For agent-integration bugs: the agent name + version, and the output
  of `IsleSetup diagnose <agent>`.
- Steps to reproduce, expected vs actual behaviour.

## Code of conduct

By participating you agree to abide by the project Code of Conduct
(see [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)).

---

Thanks for helping make Isle better.
