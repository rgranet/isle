# Isle — project memory for AI assistants

This file is the persistent context any AI assistant (Claude Code, Cursor,
Codex, etc.) should read first when working on this repo. Keep it terse,
factual, and up to date.

---

## 1. What Isle is

**Isle** is a macOS 14+ utility that turns the MacBook notch into a Dynamic
Island AND a live control surface for AI coding agents (Claude Code, Codex,
Cursor, Gemini CLI, Kimi, OpenCode, plus a few Claude-Code-compatible forks:
Qoder, Qwen Code, Factory, CodeBuddy).

Tagline: *Live activities. Live agents. One isle.*

Sold as a personal product by `withmii` (bundle ID `com.withmii.isle`).
macOS App Store distribution is **not** an option — see GPL section below.

## 2. Lineage & licensing — non-negotiable

Isle is a GPL v3 fork. Two upstream projects:

1. **Atoll** — <https://github.com/Ebullioscopic/Atoll> — Dynamic Island for
   Mac. Itself a fork of `boring.notch`. Provides 99% of the visual shell:
   notch geometry, animations, media controllers (Music/Spotify/Amazon/
   YouTube), system HUD, lock screen, settings infrastructure, ~60 manager
   classes.
2. **open-vibe-island** — <https://github.com/Octane0411/open-vibe-island> —
   the coding-agent backend. Provides hook protocols, BridgeServer (Unix
   socket IPC), per-agent installers, transcript discovery, process
   resolution.

Both upstreams are GPL v3 → Isle is GPL v3 → **the binary cannot be sold on
the Mac App Store** (Apple's terms conflict with GPL anti-DRM). Distribution
is DMG via your own hosting only.

**Every file modified from upstream MUST keep the original copyright header**
(`Atoll Contributors`, `boring.notch`). My own new files use a shorter
`Isle (built on Atoll / DynamicIsland)` preamble. The `NOTICE` file at root
documents the dual lineage for GPL compliance.

Files I created from scratch live in:
- `DynamicIsland/managers/AgentHookBridgeManager.swift`
- `DynamicIsland/managers/AgentHookInstallerService.swift`
- `DynamicIsland/managers/AgentPermissionPresenter.swift`
- `DynamicIsland/managers/AgentPermissionSoundPlayer.swift`
- `DynamicIsland/managers/AgentSessionJumpback.swift`
- `DynamicIsland/managers/AgentSessionStore.swift`
- `DynamicIsland/managers/AgentTerminalDetector.swift`
- `DynamicIsland/components/Notch/NotchCodingAgentsView.swift`
- `DynamicIsland/components/Notch/AgentPermissionSheet.swift`
- `DynamicIsland/components/Settings/CodingAgentsSettings.swift`
- `DynamicIsland/components/Live activities/CodingAgentAttentionLiveActivity.swift`
- `DynamicIsland/components/Onboarding/CodingAgentsOnboardingView.swift`
- `DynamicIsland/models/PermissionHistoryEntry.swift`
- `DynamicIsland/extensions/Color+Hex.swift`
- `DynamicIsland/managers/AppleWeatherKitService.swift`
- `DynamicIsland/MediaControllers/PodcastsController.swift`
- `DynamicIsland/managers/PrintJobManager.swift`
- `DynamicIsland/components/Printing/PrintLiveActivity.swift`
- `DynamicIsland/printing/IslePrintQueueReader.h` / `.m` (ObjC ↔ libcups bridge)
- `scripts/embed-isle-hooks.sh`
- `scripts/release.sh`
- `scripts/exportOptions.plist`

The vendored open-vibe-island source lives in
`Packages/IsleCore/.vendor/open-vibe-island/` — **read-only reference**, not
shipped. Gitignored.

## 3. Architecture

```
DynamicIslandAI/                     ← project root
├── DynamicIsland.xcodeproj          ← the app target (descends from Atoll)
├── DynamicIsland/                   ← app sources, mostly upstream Atoll
│   ├── DynamicIslandApp.swift       ← @main App + AppDelegate
│   ├── ContentView.swift            ← 2900+ lines, the notch UI dispatcher
│   ├── DynamicIslandViewCoordinator.swift
│   ├── managers/                    ← ~60 .shared singletons (Atoll style)
│   │   ├── AgentSessionStore.swift          ← Isle: @Published sessions store
│   │   ├── AgentHookBridgeManager.swift     ← Isle: owns BridgeServer
│   │   ├── AgentHookInstallerService.swift  ← Isle: per-agent install router
│   │   ├── AgentTerminalDetector.swift      ← Isle: walks process tree
│   │   ├── AgentSessionJumpback.swift       ← Isle: focus terminal
│   │   ├── AgentPermissionSoundPlayer.swift ← Isle: audio cue
│   │   ├── AgentPermissionPresenter.swift   ← Isle: floating-window mode (unused; v1 uses inline)
│   │   ├── PrintJobManager.swift            ← Isle: polls CUPS, drives print live activity
│   │   └── ScreenRecordingManager.swift     ← upstream + DisplayLink whitelist patch
│   ├── printing/
│   │   └── IslePrintQueueReader.h / .m      ← Isle: ObjC ↔ libcups bridge (in bridging header)
│   ├── MediaControllers/
│   │   ├── PodcastsController.swift         ← Isle: M8 add
│   │   └── (AppleMusic/Spotify/Amazon/YouTube/NowPlaying — upstream)
│   ├── components/
│   │   ├── Notch/
│   │   │   ├── NotchCodingAgentsView.swift  ← Isle: the Agents tab
│   │   │   └── (NotchHomeView, NotchTerminalView, …, upstream)
│   │   ├── Live activities/
│   │   │   └── CodingAgentAttentionLiveActivity.swift ← Isle: closed-notch badge
│   │   ├── Printing/
│   │   │   └── PrintLiveActivity.swift      ← Isle: closed-notch printer badge ("1 of 1")
│   │   ├── Settings/
│   │   │   ├── CodingAgentsSettings.swift   ← Isle: Settings → Coding Agents pane
│   │   │   └── SettingsView.swift           ← upstream, patched to add the tab case
│   │   └── Onboarding/
│   │       └── CodingAgentsOnboardingView.swift ← Isle: onboarding step
│   ├── DynamicIsland-Bridging-Header.h      ← imports AudioBridge.h + printing/IslePrintQueueReader.h
│   ├── enums/generic.swift                  ← patched: added `.codingAgents` to NotchViews
│   ├── models/Constants.swift               ← patched: Defaults keys for the integration
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset               ← user's Isle icon
│   │   ├── MenuBarIcon.imageset             ← user's menubar icon (template)
│   │   └── claudeicon / codexicon / cursoricon / geminiicon imageset
│   └── opencode-plugin.js                   ← Isle: JS plugin shipped to ~/.config/opencode/
├── Packages/
│   └── IsleCore/                    ← SwiftPM, local dep
│       ├── Package.swift            ← library + IsleHooks + IsleSetup executables
│       └── Sources/
│           ├── IsleCore/            ← 33 .swift files, ~10k lines (all GPL v3)
│           │   ├── AgentSession.swift / AgentEvent.swift / AgentMetadataStubs.swift
│           │   ├── Claude/ Codex/ Cursor/ Gemini/ Kimi/ OpenCode/  ← per-agent
│           │   ├── Terminal/        ← Warp SQLite reader, process resolver, locator
│           │   ├── IPC/             ← BridgeTransport + BridgeServer + clients
│           │   ├── Models/          ← SessionState, AgentIntentStore, …
│           │   ├── Hooks/           ← HookHealthCheck, HookSkipConfiguration
│           │   ├── Utilities/       ← TimedCache, WorkspaceNameResolver
│           │   └── ActiveAgentProcessDiscovery.swift
│           ├── IsleHooks/main.swift          ← CLI: hooks ⇒ socket forwarder
│           ├── IsleSetup/main.swift          ← CLI: install/uninstall hooks
│           └── .vendor/open-vibe-island/     ← vendored source (gitignored)
├── scripts/
│   ├── embed-isle-hooks.sh          ← Xcode Run Script: copy + codesign CLIs into bundle
│   ├── release.sh                   ← one-shot: build + archive + notarize + DMG + appcast
│   └── exportOptions.plist          ← Developer-ID export config
├── docs/
│   ├── auto-update-strategy.md      ← Sparkle workflow when you're ready to ship updates
│   └── m9-xcode-setup.md            ← one-time Xcode steps
├── Updates/appcast.xml              ← Sparkle feed (empty stub for v1)
├── NOTICE                           ← GPL lineage attribution
├── README.md / CONTRIBUTING.md
└── LICENSE                          ← GPL v3
```

### Data flow when Claude triggers a permission

```
Terminal: `claude` running
    │
    │ Claude PreToolUse hook fires
    ▼
~/.claude/settings.json points to:
~/Library/Application Support/Isle/bin/IsleHooks --source claude
    │
    │ reads JSON payload on stdin, encodes via BridgeTransport
    ▼
Unix socket at ~/Library/Application Support/openisland/bridge.sock
    │
    ▼
BridgeServer (running inside Isle.app, started at launch)
    │
    │ decodes envelope → handleClaudeHook → builds PermissionRequest
    │ → emit(.permissionRequested(…))
    │ → localState.apply(event)
    │ → onSessionsChanged?(localState.sessions)   ← M7.8 callback
    ▼
AgentHookBridgeManager.shared (hops to MainActor)
    │
    ▼
AgentSessionStore.applyLiveSnapshot(sessions)
    │
    │ @Published sessions = merged   ← didSet fires
    │   ├─ reconcilePermissionTracking → starts expiry timer + plays sound
    │   └─ handleAttentionTransition → switches coordinator.currentView = .codingAgents
    ▼
SwiftUI re-renders:
    • CodingAgentAttentionLiveActivity (closed notch) — orange brand badge
    • NotchCodingAgentsView (open notch, Agents tab) — pulsing card +
      inline Yes/No buttons + suggested-rule pills + expiry bar
    │
    │ User clicks "Yes"
    ▼
AgentSessionRow.resolve(.allowOnce())
    │
    │ AgentSessionStore.recordUserDecision(.allowed, for: sessionID)
    │ AgentHookBridgeManager.resolvePermission(sessionID, resolution)
    ▼
BridgeServer.resolvePermission (public method)
    │
    │ queues to internal serial queue
    │ self.handle(.resolvePermission(…), from: fakeClientID)
    │   → resolvePendingClaudeInteraction → writes directive back over socket
    │ onSessionsChanged?(localState.sessions)   ← explicit re-notify after resolve
    ▼
AgentSessionStore receives cleared sessions
    │
    │ didSet detects permissionRequest cleared
    │   → moves entry to permissionHistory with .allowed verdict
    │   → clears permissionStartTimes
    ▼
UI clears: badge gone, pulse stops, card normal, history row appears
    │
    ▼
Back in terminal: Claude receives the directive, executes the tool, continues
```

## 4. Critical conventions

### Bundle ID and product name
- App bundle ID: `com.withmii.isle` (Release) / `com.withmii.isle.dev` (Debug)
- Product name: `Isle.app`
- Display name: `Isle`
- Helpers install path on user disk: `~/Library/Application Support/Isle/bin/IsleHooks` (current) with fallback to `OpenIsland`/`VibeIsland` paths for users migrating from upstream.

### BridgeSocketLocation — NOT rebranded
The Unix socket still lives at `~/Library/Application Support/openisland/bridge.sock`. This is intentional: rebranding requires migration logic for users with running hooks pointing at the old path. Deferred to v1.x.

### AtollExtensionKit dependency — kept as-is
`https://github.com/Ebullioscopic/AtollExtensionKit` is the one external GPL dep we kept. Provides extension types (`AtollLiveActivityDescriptor`, `AtollDistributedNotifications`, etc.) that other apps use to push content into the notch. Forking would mean maintaining a parallel kit; not worth it for v1.

### Synchronized Xcode groups
Atoll uses `PBXFileSystemSynchronizedRootGroup`. New `.swift` files dropped into `DynamicIsland/managers/` or `DynamicIsland/components/...` are auto-picked-up by the build. No pbxproj editing needed for source additions.

### Sparkle disabled for v1
- `Info.plist` has `SUEnableAutomaticChecks = false`
- `SPUStandardUpdaterController(startingUpdater: false, …)` in `DynamicIslandApp.init()`
- Feed URL placeholder `https://updates.withmii.com/isle/appcast.xml` — not hosted
- To re-enable: flip both to `true` once the host is set up. See `docs/auto-update-strategy.md`.

### DisplayLink false positive (recording indicator)
`ScreenRecordingManager` was producing a permanent red recording indicator because `CGSIsScreenWatcherPresent()` returns true whenever DisplayLink Manager is running (legitimately driving an external monitor). Patched: a `knownBenignScreenWatchers` set is checked first; if DisplayLink / Duet / Synergy / spacedesk / Luna Display is running, the indicator is suppressed. Trade-off: real screen recordings won't be flagged while one of those apps runs.

## 5. Build & release

### Local Debug
- Open `DynamicIsland.xcodeproj` in Xcode 16+
- Cmd-R → runs the Debug target signed with `Apple Development`

### Release (signed + notarized DMG)
```sh
./scripts/release.sh 1.0.0
```
Takes 5-15 min. Steps:
1. `swift build -c release --package-path Packages/IsleCore` (CLIs)
2. `xcodebuild archive` → signed .app via Developer ID
3. `xcodebuild -exportArchive` per `scripts/exportOptions.plist`
4. zip + `notarytool submit --wait` (.app)
5. `stapler staple` (.app)
6. `hdiutil create` (DMG) — or `create-dmg` if installed for prettier UI
7. `notarytool submit --wait` (DMG) — DMG container needs its own ticket
8. `stapler staple` (DMG)
9. Generates `Isle-<version>.appcast.xml` stub

### Prerequisites for release.sh
- Apple Developer Program (`Developer ID Application` cert in Keychain)
- Stored notarytool credential: `xcrun notarytool store-credentials ISLE_NOTARY --apple-id … --team-id U4F34B3YF9 --password APP_SPECIFIC_PASSWORD`
- `scripts/exportOptions.plist` has the right team ID (`U4F34B3YF9`)
- `Info.plist` `SUPublicEDKey` matches the Sparkle private key in your Keychain

### Embed Run Script in Xcode
Xcode → DynamicIsland target → Build Phases → Run Script phase named "Run Script" (or rename to "Embed IsleHooks + IsleSetup"). Already configured. Inputs:
- `$(SRCROOT)/Packages/IsleCore/.build/release/IsleHooks`
- `$(SRCROOT)/Packages/IsleCore/.build/release/IsleSetup`

Outputs:
- `$(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/IsleHooks`
- `$(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/IsleSetup`

Script: `"${SRCROOT}/scripts/embed-isle-hooks.sh"`

**Critical**: the script codesigns the helpers with `--options runtime` so they have hardened runtime enabled (Apple notarization requirement). Without this, notarization fails.

## 6. Adding a new coding agent

To add support for, e.g., a new agent called "Foo":

1. **Agent identity** — add `case foo` to `AgentTool` enum in `Packages/IsleCore/Sources/IsleCore/AgentSession.swift`, with `displayName`, `shortName`, `brandColorHex`.
2. **Per-agent backend** — port (or write) hook handler, installer, metadata in `Packages/IsleCore/Sources/IsleCore/Foo/`. Use `Claude/` as template.
3. **Wire installer** — add `.foo` branch to `AgentHookInstallerService.runInstall / runUninstall / fetchStatus` in `DynamicIsland/managers/`.
4. **Wire bridge handler** — add `handleFooHook` to BridgeServer if needed.
5. **Icon asset** — drop `fooicon.imageset` in Assets, add to `CodingAgentAttentionLiveActivity.iconAssetName(for:)`.
6. **Settings UI** — no change needed; `AgentTool.allCases` is iterated automatically by `CodingAgentsSettings`.
7. **Config consent dialog path** — add `.foo` case to `AgentInstallRow.configFilePathDescription` in `CodingAgentsSettings.swift`.

## 7. Gotchas

- **Hover-open detection is fragile.** Any new live activity view in ContentView's else-if chain MUST avoid `.contentShape(Rectangle())` and `.frame(height:)` pinning — they swallow hover events and break the notch. Mirror `MusicLiveActivity` structure (3-section HStack derived from `vm.effectiveClosedNotchHeight`).
- **Scroll inside notch closes it.** Any new tab view MUST call `vm.setScrollGestureSuppression(true, token:)` and `vm.setAutoCloseSuppression(true, token:)` on hover (and `false` on disappear). See `NotchCodingAgentsView.updateSuppression`.
- **5-second polling overwrites hook state.** `AgentSessionStore.refreshSessions` now preserves `isHookManaged` sessions explicitly. Don't bypass.
- **Resolve doesn't go through `emit()`.** BridgeServer's `handle(.resolvePermission)` mutates `localState` directly. My public `resolvePermission(sessionID:resolution:)` re-fires `onSessionsChanged` manually after `handle` returns — don't remove that.
- **Demo sessions concept is gone.** A simulation feature was added then removed at user's request. Code is clean of `.demo` origin branches now.
- **Atoll attribution in GPL headers.** A bulk `Atoll → Isle` sed pass overwrote those once; we restored them. If you ever do another bulk rebrand, exclude `* Atoll Contributors`, `* Modified and adapted for Atoll`, etc.
- **Dock badge title equality is fragile.** macOS Catalyst apps ship `CFBundleDisplayName` prefixed with invisible Unicode bidi marks (e.g. WhatsApp = `‎WhatsApp` with `U+200E`). `DockBadgeReader.strippingBidiMarks()` normalises titles before the dictionary insert. If you add a new app to `MessagingApp.dockTitles` and it "silently fails to match", check the raw title in Settings → Messaging → Raw Dock badges (debug).
- **WeatherKit needs portal setup, not just the entitlement.** `DynamicIsland.entitlements` carries `com.apple.developer.weatherkit`, but the native `WeatherService` only authenticates when the App ID (`com.withmii.isle` **and** `com.withmii.isle.dev`) has the **WeatherKit** capability enabled in the Apple Developer portal AND the build embeds a provisioning profile that includes it. Since Isle ships Developer-ID (non-App-Store), `release.sh` signing must embed that profile (`--provisioning-profile` / `embedded.provisionprofile`). Until the portal step is done, **even local Debug builds fail to codesign** because automatic signing can't add a capability the App ID doesn't have. The code degrades gracefully at runtime — `AppleWeatherKitService.fetch` throws when unauthenticated and both `NotchWeatherManager` and `LockScreenWeatherManager` fall back to Open-Meteo — but the *build/sign* step is the hard gate. WeatherKit's ToS also require visible "Weather" attribution + legal link; currently surfaced only in Settings → Weather footer (notch/lock-screen attribution UI is a TODO).
- **`activityUpdated(.running)` preserves pending approval state by design.** SessionState's `preservesActionableState` heuristic refuses to clear `permissionRequest` when a generic `.running` activity event arrives mid-approval. The only way out is `actionableStateResolved` / `sessionCompleted` / a new `permissionRequested`. Every PostToolUse / PostToolUseFailure path in `BridgeServer` MUST emit `actionableStateResolved` before `activityUpdated`, otherwise stale permission cards stick on screen when the user answers in the terminal TUI.
- **Print live activity rides libcups via an ObjC bridge.** The notch printer badge (`PrintLiveActivity`, fed by `PrintJobManager` polling every 2 s, gated by `Defaults[.enablePrintListener]`) reads the CUPS queue through `printing/IslePrintQueueReader.{h,m}` — `cupsGetJobs` for active jobs plus a per-job IPP `Get-Job-Attributes` request for `job-media-sheets[-completed]` (falls back to impressions). Swift never imports `<cups/cups.h>`; the ObjC `.m` does, and only Foundation types cross into Swift via the bridging header. **Linking needs `OTHER_LDFLAGS = -lcups`** in the app target (both Debug + Release build settings in the pbxproj) — without it you get undefined `cupsGetJobs`/`ippNewRequest` symbols at link time. CUPS APIs are Apple-"deprecated" but still the only supported queue reader, so the `.m` wraps everything in `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`. The `1 of 1` page label only appears when the driver reports sheet counts; otherwise the badge shows with a spinner. The bridge does blocking IPP calls, so `PrintJobManager` polls off the main queue (`pollQueue`) and hops back to `@MainActor` to publish. App sandbox is OFF, so connecting to the local cupsd socket just works; if it's ever re-enabled, CUPS access will need a sandbox exception.

## 8. Known limitations / deferred work

- **Per-pane jumpback** (Warp pane UUIDs, iTerm2 window IDs) is roughed in via `AgentTerminalDetector` but only focuses the *app*, not the specific tab. The vendored `WarpSQLiteReader` is ready to use.
- **Status line installer** (`ClaudeStatusLineInstallationManager` from IsleCore) is ported but not surfaced in Settings UI.
- **OpenCode plugin** (`opencode-plugin.js` in bundle) still references the old `OPEN_ISLAND_SOCKET_PATH` env var — works because BridgeServer also still listens on that path. Rebrand together when the socket location is migrated.
- **macOS system UNUserNotification** as fallback when Isle isn't running on the active display — not implemented.
- **Multi-session attention** works but the closed-notch badge only shows the first attention session. Pulse logic could be smarter for >1.
- **Sparkle hosting** — feed URL `https://updates.withmii.com/isle/appcast.xml` is a placeholder. v1.0 ships with auto-update disabled.
- **Bluetooth HUD animations missing** — when pushing the initial commit to `github.com/rgranet/isle`, all Git LFS files were dropped (they were never resolved locally, just pointer stubs from the shallow Atoll clone). The repo no longer ships the AirPods/Beats 3D `.mov` animations in `DynamicIsland/BluetoothHUDAnimations/` (airpods, airpodsGen3/Gen4/Max/Pro/Pro3, beatssolo, beatsstudio) nor `DynamicIslandSamples/dynamicislandscreenrecord.gif`. `.gitattributes` was also emptied so no new LFS tracking is active. **TODO**: source replacement assets (record them, grab from Atoll upstream, or supply Isle-branded ones), drop them back into `DynamicIsland/BluetoothHUDAnimations/` with the same filenames, and commit them as regular binaries (no LFS) — they are small enough.

## 9. Useful one-liners

```sh
# Reset onboarding for testing
defaults delete com.withmii.isle.dev firstLaunch 2>/dev/null
defaults delete com.withmii.isle firstLaunch 2>/dev/null

# See what's in Claude's settings.json
cat ~/.claude/settings.json | python3 -m json.tool | grep -A 4 hooks

# Verify managed binary exists
ls -la ~/Library/Application\ Support/Isle/bin/

# Kill any running Isle before debugging
pkill -f "Isle\.app" ; sleep 1

# Re-run notarization on an existing DMG (if it failed partway)
xcrun notarytool submit build/release/<version>/Isle-<version>.dmg \
    --keychain-profile ISLE_NOTARY --wait
xcrun stapler staple build/release/<version>/Isle-<version>.dmg

# Inspect a notarization failure
xcrun notarytool log <submission-id> --keychain-profile ISLE_NOTARY
```

## 10. Version history (high level)

| Version | What landed |
|---|---|
| 1.0.0 | Initial public release. All 10 coding agents recognised, hook install for 6 (Claude+forks, Codex, Cursor, Gemini, Kimi, OpenCode), Podcasts media controller, full attention UX (sound + expiry bar + history), Welcome onboarding step, signed + notarized DMG, Sparkle disabled. |
| 1.1.0 | Weather notch tab (Open-Meteo + wttr.in, shares lock-screen widget defaults), messaging-app monitor (WhatsApp / Teams / Slack / iMessage / Discord via Dock badge AX read), notification-text-behind-physical-notch fix on multi-display setups. |
| 1.1.1 | WhatsApp Dock title matching: strip invisible Unicode bidi marks (`U+200E` LRM etc.) in `DockBadgeReader` because WhatsApp's `CFBundleDisplayName` is `‎WhatsApp`. Discord noise fix: per-app `acceptsNonNumericBadge` (Discord = `false`) so the gray "any server unread" dot no longer fires a notif — only the numeric badge (DMs / @mentions) does. |
| 1.2.0 | Apple Weather (WeatherKit) as the **default** weather provider, with Open-Meteo / wttr.in kept as automatic fallbacks. New `AppleWeatherKitService` wraps native `WeatherService`, maps `WeatherCondition` → WMO codes so it reuses `OpenMeteoSymbolMapper` icons + `NotchWeatherView` tints. Wired into both `NotchWeatherManager` (notch tab) and `LockScreenWeatherManager` (lock-screen widget); both silently fall back to Open-Meteo if WeatherKit is unauthenticated. Added `com.apple.developer.weatherkit` entitlement. **Requires** the WeatherKit capability enabled for `com.withmii.isle`(+`.dev`) in the dev portal + an embedded provisioning profile — see Gotchas. |
| 1.1.2 | Discord Canary / PTB / Development variants supported (`dockTitle: String` → `dockTitles: [String]` in `MessagingApp`). Teams "work or school" variant. Empty states for Messages + Agents tabs made visible (was `.tertiary` ≈ invisible on dark notch). Stale permission-request fix: PostToolUse / PostToolUseFailure of Claude / Codex / OpenCode now emit `actionableStateResolved` before `activityUpdated`, so a card no longer sticks around after the user answered in the terminal TUI. Debug "Raw Dock badges" section added to Settings → Messaging for future per-app tuning. |
| 1.2.4 | Settings polish: fullscreen-exception toggles moved Media → General as iOS-style switches, About cleanup (GitHub link → `rgranet/isle` + light-mode-visible template logo, Donate → pricing page, new Website button), messaging toggles as colored switches. New **print live activity**: `IslePrintQueueReader` (ObjC bridge to libcups, `cupsGetJobs` + IPP `Get-Job-Attributes`) feeds `PrintJobManager` (2 s poll) and `PrintLiveActivity` — a closed-notch printer badge with "1 of 1" page progress, gated by `Defaults[.enablePrintListener]` (Settings → General → Printing). Links `libcups` via `OTHER_LDFLAGS = -lcups`. Build 20. |

Future versions should append rows here.

---

**When you (an AI assistant) start a new session on this repo, read this whole
file before touching code.** Then check `git log --oneline | head -30` for the
freshest decisions that may not yet have made it into this document.
