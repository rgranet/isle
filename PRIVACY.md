# Isle — Privacy Policy (DRAFT)

> **DRAFT** — this document is committed to the repository as a working
> draft sourced from a code audit. It has not been published as the
> official privacy policy at <https://withmii.com/isle/privacy>. Review
> before publishing.

_Last updated: 2026-06-04 · Version covered: Isle 1.2.2_

---

## TL;DR

Isle does not collect, transmit, or sell any personal information. There
is no analytics SDK, no crash reporter, no telemetry endpoint, no
fingerprinting, no advertising identifier, and no account system. Every
network request Isle makes is either a direct consequence of a feature
you turned on or of an action you just took, and the destination of that
request is whoever owns the relevant service (Apple, Spotify, an open
weather API, the LLM provider you configured) — not a server controlled
by Isle's authors.

If you never touch a network-bound feature, Isle still phones home
exactly once on launch: it fetches the auto-update appcast from
`raw.githubusercontent.com`. That request reveals nothing more than an
anonymous GitHub user-agent hitting a public file.

---

## What Isle does not do

- **No analytics SDK** — Isle does not embed Firebase, Crashlytics,
  Sentry, Bugsnag, Mixpanel, Amplitude, PostHog, Segment, Datadog,
  Heap, AppCenter, TelemetryDeck, or any equivalent tracker.
- **No advertising identifier** — Isle never reads `ASIdentifierManager`
  or `identifierForVendor`.
- **No background telemetry session** — Isle does not use
  `URLSessionConfiguration.background` for any kind of usage reporting.
- **No heartbeat / ping** — Isle does not periodically contact any
  server owned by the project.
- **No account** — Isle has no sign-in, no email collection, no profile.
- **No data sale** — there is no data to sell.

---

## What network requests Isle makes, and when

All requests below are scoped to a specific feature. Each feature can
be turned off in Settings; the request stops the moment the feature is
disabled. Each request only sends data the user has explicitly chosen
to surface or share through that feature.

### Auto-update (always on by default; turn off in Settings → About)

- **Endpoint:** `raw.githubusercontent.com/rgranet/isle/isle-main/Updates/appcast.xml`
- **When:** at every app launch and on a Sparkle-internal cadence.
- **What is sent:** a standard `HTTP GET`. No system profile is
  attached (`SUSendProfileInfo` is unset, so Sparkle does **not** send
  CPU model, OS version, language, or other anonymous fingerprinting).
- **Why:** to learn whether a newer version of Isle is published.
  Downloaded updates come from the same `github.com/rgranet/isle/releases`
  host and are verified against an EdDSA signature embedded in the app.

### Weather (Settings → Weather; off until you enable)

- **Endpoints:** `api.open-meteo.com`, `air-quality-api.open-meteo.com`,
  `wttr.in`.
- **What is sent:** a latitude/longitude (rounded), and only when you
  open the Weather tab or the Weather lock-screen widget asks for a
  refresh.
- **Why:** to render current conditions and the short forecast.

### Media controllers (Settings → Media)

- **Endpoints:** `api.music.apple.com`, `itunes.apple.com`,
  `accounts.spotify.com`, `open.spotify.com`,
  `spclient.wg.spotify.com`.
- **When:** only when the corresponding player (Apple Music or Spotify)
  is the currently active media source.
- **What is sent:** lookups for the artwork, track metadata, and player
  state of what is already playing on your system.
- **Why:** to render the now-playing card with correct album art and
  controls.

### Lyrics (Settings → Media)

- **Endpoint:** `lrclib.net`.
- **What is sent:** the song title and artist, only when lyrics are
  toggled on for the currently playing track.

### Lottie animation asset (one CDN fetch)

- **Endpoint:** `assets9.lottiefiles.com`.
- **When:** once per session, to load the music notch animation file.
- **What is sent:** an anonymous request for a public JSON asset.

### Screen Assistant — LLM chat (Settings → Screen Assistant; needs your own API key)

- **Endpoints:** depending on the provider you select:
  `api.anthropic.com`, `api.openai.com`, `api.groq.com`,
  `generativelanguage.googleapis.com`.
- **When:** only when you type a message or attach a screenshot inside
  the Screen Assistant and press send.
- **What is sent:** your message, any file you attach, and your own API
  key — sent directly to the LLM provider you chose. Isle is not on
  the wire and does not see, log, or proxy this traffic.
- **Why:** to fulfil your prompt. Your relationship with the LLM
  provider is governed by their privacy terms, not Isle's.
- **Disable:** set `enableScreenAssistant` to off, or simply leave the
  API key fields empty (no request is made without a key).

### Coding-agent hooks (Settings → Coding Agents)

- **Endpoint:** none over the network. The integration listens on a
  local Unix socket at
  `~/Library/Application Support/openisland/bridge.sock`.
- **What is exchanged:** JSON event payloads sent by the supported
  agents (Claude Code, Codex, Cursor, Gemini CLI, Kimi, OpenCode and
  Claude-Code-compatible forks) running locally on your Mac, when a
  permission request or session event happens.
- **Why:** to display the closed-notch attention badge and the
  inline Allow / Deny controls. Nothing about these events leaves your
  Mac.

---

## What Isle stores on your Mac

Isle uses the standard macOS `UserDefaults` plist at
`~/Library/Preferences/com.withmii.isle.plist` for all settings.

Notable items:

- Your feature toggles (which tabs are on, which animations, etc.).
- Your accent color, notch height preferences, gesture sensitivity.
- The history of recently-resolved coding-agent permission requests
  (so you can audit what was approved/denied).
- LLM API keys for the Screen Assistant, **stored in plaintext in this
  plist** rather than the macOS Keychain. Any other app running on
  your Mac with Full Disk Access can read this file. If this is a
  concern, leave the API key fields empty.
- Last-known weather location, if Weather is enabled.

In addition, Isle reads — but does not copy or transmit — the Dock's
accessibility tree to surface unread badge counts for the Messages tab
(WhatsApp, Microsoft Teams, Slack, iMessage, Discord). The counts are
held in memory and refreshed on a configurable polling interval.

Isle does not write any user-content database, analytics file, or log
file outside of macOS's own application logs.

---

## macOS permissions Isle requests

You'll see system permission prompts the first time you enable certain
features. Isle never asks for a permission outside the feature that
needs it.

| Permission | What feature needs it | Why |
|---|---|---|
| Accessibility | Messaging unread badges; coding-agent terminal focus | Reading the Dock's AX tree; focusing a terminal window when you click on a session card |
| Calendar / Reminders | Calendar tab | Reading the events you choose to display |
| Notifications | Messaging tab (optional) | Showing a system banner when a new unread arrives |
| Bluetooth | Bluetooth HUD (AirPods battery, 3D animation) | Listening for connect/disconnect and reading battery |
| Screen Recording | Screen Assistant (optional) | Capturing the screenshot you attach to a prompt |

Denying any of these gracefully disables the corresponding feature.
None of them is required for Isle to launch.

---

## Auto-update

Isle is signed with a Developer ID Application certificate issued to
Ruben Granet (`U4F34B3YF9`) and notarised by Apple. Updates are
distributed through Sparkle 2.x:

1. At launch, Isle reads the public appcast on GitHub.
2. If a newer version is listed, Isle offers an install dialog.
3. If you accept, the DMG is downloaded from the matching GitHub
   Release, its EdDSA signature is verified against the public key
   embedded in your installed Isle, and the new build replaces the old
   one.

You can turn auto-update off in Settings → About → Auto-update at any
time.

---

## Open source

Isle is licensed under the GNU General Public License version 3 and
its full source is published at <https://github.com/rgranet/isle>.
It is a fork of two upstream projects:

- [Atoll](https://github.com/Ebullioscopic/Atoll) — provides the
  Dynamic Island shell, media controllers, HUD/lock screen, and most
  of the settings infrastructure.
- [open-vibe-island](https://github.com/Octane0411/open-vibe-island) —
  provides the coding-agent backend (hooks, BridgeServer IPC,
  per-agent installers, transcript discovery).

The audit that produced this document is reproducible: every claim
above corresponds to a string or import that you can `grep` for in the
repository.

---

## Changes to this policy

When this policy is updated, the "Last updated" line at the top of
this document is bumped and the diff is visible in the repository's
git history. Material changes (a new feature that introduces a new
endpoint, a change in default behaviour) will also be mentioned in
the release notes for the version that introduced them.

---

## Contact

For privacy questions, open an issue on
<https://github.com/rgranet/isle/issues> or email the maintainer.
