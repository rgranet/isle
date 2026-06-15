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
