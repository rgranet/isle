# Isle — Changelog

This file is the single source of truth for user-facing release notes.
`scripts/release.sh` extracts the `## <version>` section for the version being
released and embeds it (as HTML) into the Sparkle appcast `<item>` as
`<description>`, so the bullet list below is exactly what users see in the
"Update Available" dialog **before** they install.

Conventions:
- One `## <version>` heading per release (e.g. `## 1.2.5`), newest on top.
- Use `- ` bullets. Keep them short, user-facing, and in English.
- Keep an `## Unreleased` section at the top while you work; rename it to the
  version number right before running `./scripts/release.sh <version>`.

## Unreleased
- New floating dock: the tab bar now floats as a detached capsule below the open notch (with a separate circular Settings button), Droppy-style. The in-panel tab row disappears when the dock is on. Toggle in Settings → Appearance → Open Notch → "Floating dock".
- Liquid glass notch: the open notch now uses a progressive Siri-style glass surface — black at the top for perfect contrast, melting into real frosted glass toward the bottom edge where the wallpaper glows through, finished with a subtle luminous rim. Tune the bottom darkness or disable it in Settings → Appearance → Open Notch. The closed notch stays black to blend with the camera housing.
- Meet the Isle mascot: a glassy little island robot now waves you in on the welcome screen and keeps the Agents and Messages empty states company (sleeping when nothing's happening, smiling at inbox zero). The menu bar icon is now its face — a pill glyph with two eyes and the status LED, adapting to light/dark as a template.
- Notification banners polished: the "new message" and "needs approval" closed-notch banners no longer clip their text against the bottom edge — the label is now a single line pinned below the camera cutout — and their icon halos use the shared breathing-glow effect.
- Widgets now integrate cleanly with the glass surface: the scroll-edge fades in Calendar, Events, Notes and Timer lists no longer paint dark bands over the panel — content fades out through a transparency mask instead. The note editor also lost its opaque black canvas and now sits directly on the glass.
- New Siri-style glowing dots spinner (liquid-glass look): the print live activity now shows a luminous orbiting-dots indicator instead of the stock spinner while page counts are unknown.
- Agent attention badges: the pulsing brand-color glow is now a shared, smoother "breathing halo" effect across all coding-agent live activities.

## 1.2.7
- Shelf: new management controls — a "Select all" / "Deselect all" toggle and an "Erase all" button in the tray, plus a delete button that appears when you hover over an item.
- Shelf: clearer selection — selected items now show a filled checkmark badge with a stronger highlight.

## 1.2.6
- Performance: drastically reduced idle CPU/energy use. The system-HUD suppression watcher no longer spawns a `pgrep` process ~7×/second (now a native in-process lookup), and Claude transcripts are only re-parsed when their files actually change (cached by modification date) instead of on every poll.

## 1.2.5
- Calendar: a "more below" chevron now appears on the events/reminders list when items are hidden under the fold, and disappears once you scroll to the bottom.
- Lyrics: Apple Music tracks now try their embedded lyrics first, with LRCLIB as a fallback; added diagnostics for missing lyrics.
- Settings: reorganized the sidebar — Messaging Apps moved to Productivity, Stats moved to System.
- New "Contributors" tab with a thank-you section and a donation option.

## 1.2.4
- New print live activity: a closed-notch printer badge with "1 of 1" page progress, driven by CUPS.
- Settings polish: iOS-style switches for fullscreen exceptions and messaging toggles, cleaner About page.

## 1.2.0
- Apple Weather (WeatherKit) is now the default weather provider, with Open-Meteo and wttr.in kept as automatic fallbacks.

## 1.1.2
- Discord Canary / PTB / Development and Microsoft Teams "work or school" variants now recognized for message badges.
- Empty states for the Messages and Agents tabs are now visible.
- Fixed stale agent permission cards lingering after answering in the terminal.

## 1.1.1
- WhatsApp Dock badge matching fixed (invisible Unicode marks stripped).
- Discord no longer fires a notification for the gray "unread" dot — only numeric badges (DMs / mentions).

## 1.1.0
- New Weather notch tab.
- Messaging-app monitor for WhatsApp, Teams, Slack, iMessage and Discord.
- Fixed notification text showing behind the physical notch on multi-display setups.

## 1.0.0
- Initial public release: Dynamic Island for the MacBook notch plus a live control surface for AI coding agents.
