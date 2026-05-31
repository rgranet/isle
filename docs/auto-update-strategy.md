# Isle — auto-update strategy

This is the long-form explainer for how releases reach users. The short
version is in `scripts/release.sh`.

## TL;DR

Isle uses **[Sparkle](https://sparkle-project.org)**, the de-facto OSS
auto-updater for macOS apps distributed outside the Mac App Store. Every
launch the app fetches a small XML file (an "appcast") from your server,
compares the listed version to its own, and offers an update if newer.

```
┌─ User's Mac ──────────────────┐         ┌─ updates.withmii.com ─────────┐
│                               │  GET    │                               │
│  Isle.app (Sparkle inside)  ──┼────────▶│   appcast.xml                 │
│                               │         │   Isle-1.2.3.dmg              │
│             ▲                 │         │   Isle-1.2.4.dmg              │
│             │   download DMG  │  GET    │                               │
│             └─────────────────┼─────────│                               │
└───────────────────────────────┘         └───────────────────────────────┘
```

## One-time setup (do this once, on your dev mac)

### 1. Apple Developer Program

You need a **Developer ID Application** certificate from Apple
(USD 99/year). Once enrolled:

- In Xcode → Settings → Accounts → add your Apple ID
- Download the **Developer ID Application** cert into your Keychain
- Confirm with `security find-identity -v -p codesigning` — you should see one line ending in `(TEAMID12 …)`

### 2. Notarisation credential

Apple notary service needs an **app-specific password**:

- Go to appleid.apple.com → Sign In → App-Specific Passwords → Generate one, label it `notary-isle`
- Store it in Keychain so the release script can read it non-interactively:
  ```sh
  xcrun notarytool store-credentials ISLE_NOTARY \
      --apple-id  you@example.com \
      --team-id   TEAMID12CHARS \
      --password  "the-app-specific-password-you-just-made"
  ```
- The release script reads `${NOTARY_KEYCHAIN_PROFILE:-ISLE_NOTARY}` so as long as you keep this name, no env var is needed.

### 3. Sparkle EdDSA key pair

This is what stops a hostile DNS server from feeding your users a fake update.

- Download Sparkle: <https://github.com/sparkle-project/Sparkle/releases>
- Inside the zip there's `bin/generate_keys`. Run it once:
  ```sh
  ./generate_keys --account isle-release
  ```
- It saves the **private** key in your Keychain and prints the **public** key.
- Paste the public key into `DynamicIsland/Info.plist`:
  ```xml
  <key>SUPublicEDKey</key>
  <string>THE_BASE64_PUBLIC_KEY_HERE</string>
  ```
- Sparkle's `sign_update` tool will read the private key from your Keychain to sign each DMG.

### 4. Hosting

The appcast and DMGs need to live at HTTPS URLs reachable from any user's Mac. Options:

- **GitHub Releases** (free) — point `SUFeedURL` to a raw URL like `https://raw.githubusercontent.com/withmii/isle/main/Updates/appcast.xml`. DMGs uploaded as release assets get permanent CDN URLs.
- **Cloudflare R2 / Backblaze B2 / S3** (cheap) — set up a CNAME like `updates.withmii.com` → bucket; upload the appcast and DMGs via API.
- **Your own server** — anywhere serving static files over HTTPS works.

Whichever you pick, `Info.plist`'s `SUFeedURL` must match. We currently ship a placeholder `https://updates.withmii.com/isle/appcast.xml`.

### 5. Edit `scripts/exportOptions.plist`

Replace the `TEAMID12CHARS` placeholder with your real 10-character Apple team ID.

## The release flow

Once setup above is done, every release is:

```sh
./scripts/release.sh 1.0.0
```

That script (see source for inline comments):

1. Builds `IsleHooks` and `IsleSetup` in Release mode
2. Archives the `DynamicIsland` Xcode scheme
3. Exports a Developer-ID-signed `Isle.app`
4. Submits the zipped `.app` to Apple's notary; waits for the ticket
5. Staples the ticket onto the `.app` so Gatekeeper accepts it offline
6. Builds a pretty DMG (`create-dmg` if installed, else `hdiutil`)
7. Signs the DMG with the Sparkle EdDSA private key
8. Spits out a ready-made appcast `<item>` block at `build/release/<version>/Isle-<version>.appcast.xml`

Then **you**:

9. Upload the DMG to your CDN bucket
10. Paste the `<item>` block at the top of `<channel>` in `Updates/appcast.xml`
11. Push `Updates/appcast.xml` to the URL set in `SUFeedURL`

That's the full release loop — should take <10 min once setup is done.

## What users see

- They launch Isle (any prior version)
- Sparkle fetches the appcast in the background within ~5 s
- If the appcast lists a newer version, a small "Update Available" dialog appears (the standard Sparkle UI)
- User clicks "Install Update", the new DMG downloads in the background, the app relaunches itself with the new build
- Or they ignore — Sparkle will ask again at the next launch, with an exponential back-off

Users who **don't** want updates can switch them off in Settings → General → Auto-update.

## Release cadence — recommendation

For a personal-product Mac app, **fortnightly minor releases** + ad-hoc patch releases is a good rhythm. Sparkle handles even quick-fire patch releases cleanly because the DMG diff is small (Sparkle supports delta updates if you generate them, but ZIP-form DMG works fine for an app < 50 MB).

Version scheme:
- `MAJOR.MINOR.PATCH` (semver-ish — Sparkle compares strings smartly)
- Bump `CFBundleShortVersionString` (user-facing) AND `CFBundleVersion` (build number, monotonic integer) in `Info.plist` for every release.

## What we deferred (M9 follow-ups)

- **Delta updates** — Sparkle supports binary deltas (`generate_appcast` tool). Skip until you're shipping > 50 MB binaries.
- **Beta channel** — Sparkle natively supports multiple feeds. Add `https://updates.withmii.com/isle/beta-appcast.xml` later for testers.
- **Phased rollout** — Sparkle supports `sparkle:phasedRolloutInterval` — useful only at scale.

## Pre-1.0 freeze list

- [ ] Apple Developer Program enrolled, Developer ID cert in Keychain
- [ ] `xcrun notarytool store-credentials ISLE_NOTARY …` ran
- [ ] Sparkle EdDSA key pair generated, public key in Info.plist
- [ ] CDN bucket / GitHub Releases set up, `SUFeedURL` updated to match
- [ ] `scripts/exportOptions.plist` has your real team ID
- [ ] Initial `appcast.xml` published at the SUFeedURL (can be empty `<channel>`)
- [ ] `./scripts/release.sh 1.0.0` runs to completion
- [ ] First upload + appcast publish
- [ ] Manual smoke test: install 0.9.0, then make 1.0.0 available, watch Sparkle offer the update
