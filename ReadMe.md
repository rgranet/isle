<p align="center">
  <img src="docs/assets/isle-logo.png" alt="Isle logo" width="120">
</p>

<h1 align="center">Isle</h1>

<p align="center"><em>Live activities. Live agents. One isle.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"/>
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"/>
  <img src="https://img.shields.io/badge/License-GPL%20v3-blue?style=for-the-badge" alt="GPL-3.0"/>
  <img src="https://img.shields.io/badge/Local--First-no%20telemetry-0a84ff?style=for-the-badge" alt="Local-first, no telemetry"/>
</p>

<p align="center">
  Isle puts the iPhone Dynamic Island on your Mac — and fuses it with a live control surface for your AI coding agents.
</p>

<p align="center">
  <img src="docs/assets/hero.png" alt="Isle hero" width="920">
</p>

---

## Why Isle?

The notch on every modern MacBook is wasted screen real estate. Isle treats it like Apple treats the Dynamic Island on iPhone: a single, contextual surface that **shows you what's happening right now** — what's playing, what's downloading, what's recording, what's charging.

Then it goes one step further. Isle is the first Dynamic Island for macOS with **first-class live activities for AI coding agents**. While Claude Code is thinking, while Codex is editing files, while Cursor is running a tool — you see it in the notch. Approve, interrupt, or just glance. No new window. No focus tax.

Isle is **local-first**. There is no analytics SDK, no crash reporter calling home, no account to make. It is **free as in freedom** — GPL v3, forever, with the source for every binary you run.

<p align="center">
  <img src="docs/assets/agents.png" alt="Coding agents in the island" width="920">
</p>

---

## Features

### Media

- Apple Music
- Spotify
- **Apple Podcasts**
- YouTube Music
- Amazon Music
- Generic `MediaRemote` fallback for anything else playing audio
- Inline album art, scrubber, AirPlay route, and lyrics where available

### Coding Agents

Isle ships hooks for ten coding agents out of the box. Toggle any of them on from **Settings → Coding Agents** and Isle will install a hook that surfaces tool calls, approvals, and completion events in the island.

| Agent | What you see in the island |
|---|---|
| **Claude Code** | Tool calls, approval prompts, todo list progress, completion |
| **OpenAI Codex** (CLI) | Command execution, file edits, run results |
| **Cursor** | Agent state, file edits, terminal commands |
| **OpenCode** | Session events, tool use, completion |
| **Gemini CLI** | Prompt lifecycle, tool calls |
| **Kimi** (Moonshot CLI) | Session state, message events |
| **Aider** | Edit batches, commit events |
| **Continue** | Step progress |
| **Goose** | Recipe runs, tool calls |
| **Block Goose** | Session state |

> Don't see your agent? Hooks are plain JSON written to a watched directory — adding a new agent is a few dozen lines. See `Packages/IsleCore` for the schema.

### System

- Battery & charging activity (with cycle count and health)
- CPU, GPU, memory, network, disk live stats
- Brightness / volume / keyboard backlight HUD
- Lock screen widgets (media, weather, timers, Bluetooth)
- AirDrop, file dock, and shelf
- Bluetooth device battery

### Productivity

- Pomodoro / countdown timer
- Sticky notes
- Clipboard history with search
- System color picker
- Shelf — drag any file onto the island, drop it anywhere later
- Calendar peek

### Live Activities

- Screen recording indicator
- Camera / microphone privacy indicator
- Focus / Do Not Disturb state
- Download progress (beta)
- Charging start / unplug haptic-feel animations
- Lock / unlock chimes

---

## Install

### Download the DMG (recommended)

1. Grab the latest release from the [releases page](https://github.com/withmii/isle/releases/latest).
2. Open the DMG and drag **Isle** into `Applications`.
3. Launch Isle. Grant Accessibility + Screen Recording when prompted.
4. (Optional) Open **Settings → Coding Agents** to wire up your AI tools.

### Build from source

You'll need:

- macOS 14.0 (Sonoma) or later
- Xcode 16 with the Swift 6 toolchain
- Apple Silicon recommended (Intel works for the app; agent hooks are universal)

```bash
git clone https://github.com/withmii/isle.git
cd isle

# Build the agent hook binaries used by the coding-agent integrations
swift build -c release --package-path Packages/IsleCore

# Open the app in Xcode and run
open DynamicIsland.xcodeproj
```

The `swift build` step produces two CLIs in `Packages/IsleCore/.build/release`:

- **IsleHooks** — the per-agent hook binary the app installs into your agent's config
- **IsleSetup** — a small CLI for installing / removing hooks without the GUI

The app target is `DynamicIsland`. The product bundle ID is `com.withmii.isle`.

---

## Quickstart — wire up a coding agent

Using Claude Code as the example. Other agents follow the same pattern.

1. Launch Isle.
2. Open **Settings → Coding Agents**.
3. Toggle the master switch **on**.
4. Find **Claude Code** in the list and click **Install**.
   - Isle writes a hook config to `~/.claude/settings.json` (merging, never replacing).
   - Isle copies the `IsleHooks` binary to `~/.local/share/isle/bin/`.
5. **Restart your Claude Code session.** Hooks only load on session start.
6. Run any prompt. You should see Claude Code's tool calls light up in the island.

If nothing appears, open **Settings → Coding Agents → Diagnostics** for a live event log and a "verify install" button.

To uninstall the hook for an agent, click **Uninstall** next to it. Isle removes only the keys it added; the rest of your config is untouched.

---

## Architecture (60-second version)

```
┌─────────────────────────────────────────────────────────────┐
│  DynamicIsland.app  (SwiftUI, macOS 14+)                    │
│  • Notch rendering, live activities, settings UI            │
│  • Agent event router → island surfaces                     │
└─────────────────────────────────────────────────────────────┘
                 ▲                          ▲
                 │ XPC / file watch         │ MediaRemote / IOKit
                 │                          │
┌────────────────┴────────────┐   ┌─────────┴────────────────┐
│  Packages/IsleCore           │   │  System providers         │
│  • Event schema (Codable)    │   │  • Media, battery, stats │
│  • IsleHooks  (per-agent)    │   │  • HUD, lock screen      │
│  • IsleSetup  (install CLI)  │   │  • Clipboard, shelf      │
└──────────────────────────────┘   └──────────────────────────┘
```

Each supported agent has a thin adapter in `IsleHooks` that translates the agent's native hook/event format into a stable `IsleEvent` JSON payload. The app watches a per-user event directory and renders whatever shows up. The app and the hook binaries are independently versioned, so a hook update never requires reinstalling the app — and vice versa.

For more, see [`docs/architecture.md`](docs/architecture.md).

---

## Known limitations

Being honest about what's not done yet:

- **M3.4 — Agent activity indicator (v2)**: the redesigned compact indicator (animated waveform + per-tool icons) is on the v2 track. v1 ships with a simpler pill.
- **M7.8 — Live event coalescing**: high-frequency events (e.g. Codex emitting one event per file edit during a large refactor) are not yet batched; expect a small CPU bump during very chatty sessions.
- **OpenCode plugin bundling**: OpenCode's hook system is plugin-based. We currently install a config file; the bundled plugin is targeted for the M9 final release. For now, OpenCode users may need one extra manual step (printed by `IsleSetup`).

Things we will not do: telemetry, account requirements, ads, "pro" tiers.

---

## Acknowledgements

Isle stands on shoulders.

- **[Atoll](https://github.com/Ebullioscopic/Atoll)** by Ebullioscopic — the Dynamic-Island-for-Mac base. Isle is a GPL v3 fork of Atoll.
- **[open-vibe-island](https://github.com/Octane0411/open-vibe-island)** by Octane0411 — the coding-agent hook + event-bus integration backend Isle's agent layer is derived from.
- **[boring.notch](https://github.com/TheBoredTeam/boring.notch)** by TheBoredTeam — Atoll's own upstream and the original macOS notch interaction model. Thank you.

Additional credits inherited from Atoll: Alcove (minimalistic mode inspiration), Stats (SMC + IOReport metrics), Open-Meteo (weather), SkyLightWindow (lock-screen rendering), rtaudio (visualizer), SwiftTerm (terminal tab), Wick (timer design).

See [`NOTICE`](NOTICE) for the full ancestry and credits.

---

## License

Isle is licensed under the **GNU General Public License v3.0**. Both upstreams (Atoll and open-vibe-island) are GPL v3, and Isle is a derivative work — so Isle is, and will always be, GPL v3.

The full license text is in [`LICENSE`](LICENSE). The TL;DR: use it, fork it, sell it, modify it — but if you ship a modified binary, ship the source too.

---

## Community

- Issues: [github.com/withmii/isle/issues](https://github.com/withmii/isle/issues)
- Discussions: [github.com/withmii/isle/discussions](https://github.com/withmii/isle/discussions)
- Discord: _coming soon_
- Bundle ID: `com.withmii.isle`

If Isle saves you time, the best thank-you is a star, a PR, or telling a friend with a notched MacBook.

<p align="center"><sub>Made with care for people who like their notches useful.</sub></p>
