# M9 — Xcode setup checklist

Final steps to make Isle shippable. Most of M9 happens in code (via M9-A rebrand agent and M9-B docs agent), but two things require manual Xcode UI clicks because they live in non-text Xcode project files.

## 1. Add the IsleHooks embed Run Script phase

The `IsleHooks` and `IsleSetup` CLIs need to be bundled inside `Isle.app/Contents/Helpers/` so the app can find them at runtime via `HooksBinaryLocator`.

**Steps in Xcode:**

1. Open `DynamicIsland.xcodeproj`
2. Select the `DynamicIsland` target in the project navigator
3. Click the **Build Phases** tab
4. Click the **+** button at the top-left of the phases list → **New Run Script Phase**
5. Drag the new phase so it sits **after** "Copy Bundle Resources" and **before** "Embed Frameworks"
6. Rename the phase to `Embed IsleHooks + IsleSetup`
7. In the script text box, paste exactly:
   ```sh
   "${SRCROOT}/scripts/embed-isle-hooks.sh"
   ```
8. Expand the **Input Files** section and add these two lines:
   ```
   $(SRCROOT)/Packages/IsleCore/.build/release/IsleHooks
   $(SRCROOT)/Packages/IsleCore/.build/release/IsleSetup
   ```
9. Expand the **Output Files** section and add:
   ```
   $(BUILT_PRODUCTS_DIR)/$(EXECUTABLE_FOLDER_PATH)/Helpers/IsleHooks
   $(BUILT_PRODUCTS_DIR)/$(EXECUTABLE_FOLDER_PATH)/Helpers/IsleSetup
   ```
10. **Uncheck** "Based on dependency analysis" (we want it to always run because SwiftPM build outputs can be cached out from under us)
11. Save with Cmd-S

**Pre-flight before the first Cmd-R:**

```
cd Packages/IsleCore
swift build -c release --product IsleHooks --product IsleSetup
```

Subsequent Xcode builds will rebuild on demand via the script.

**Verify it worked:**

After a Cmd-B in Xcode, the script should print:
```
Isle: embedded IsleHooks + IsleSetup → /…/Isle.app/Contents/Helpers
```

And:
```
ls "$BUILT_PRODUCTS_DIR/Isle.app/Contents/Helpers/"
# → IsleHooks  IsleSetup
```

## 2. Sparkle update feed

The `SUFeedURL` in `DynamicIsland/Info.plist` is currently a placeholder:
```
https://updates.withmii.com/isle/appcast.xml
```

**Two options:**

- **Don't ship updates yet** — leave the URL as a 404. The app will fail to fetch but won't crash. Fine for personal builds.
- **Stand up the feed** — host `appcast.xml` at that URL (or any URL of your choice), generate an EdDSA signing key pair with `generate_keys` from the Sparkle release zip, embed the public key in Info.plist as `SUPublicEDKey`, and sign each release with the private key.

Sparkle's docs: https://sparkle-project.org/documentation/

## 3. Apple Developer ID signing + notarization

Required only if you want users to launch the DMG without Gatekeeper warnings.

```
# In the project Signing & Capabilities tab, set the team to your Apple Developer ID.
# Then, for each release build:

xcodebuild -project DynamicIsland.xcodeproj \
    -scheme DynamicIsland \
    -configuration Release \
    -archivePath build/Isle.xcarchive \
    archive

xcodebuild -exportArchive \
    -archivePath build/Isle.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist scripts/exportOptions.plist

# Notarize:
xcrun notarytool submit build/export/Isle.app.zip \
    --apple-id "you@example.com" \
    --team-id "TEAMID12" \
    --password "@keychain:NOTARIZE_PASS" \
    --wait

xcrun stapler staple build/export/Isle.app
```

Create `scripts/exportOptions.plist` with `method = developer-id` once Apple Dev credentials are wired.

## 4. Wire identifiers left intentionally on legacy names

These could be rebranded but require a compat-aware migration that we deferred past v1.0:

- `_openisland._tcp` — Bonjour service name used by the Watch companion endpoint. Old open-vibe-island installs that have already published this service would conflict if we change it. Plan: add `_isle._tcp` as a parallel publish in a v1.1 migration; flip default after a release cycle.
- `~/.claude/settings.json` script identifier `"open-island-statusline"` — user-installed on disk via `ClaudeStatusLineInstallationManager`. Rebranding to `isle-statusline` needs simultaneous reading of both names so existing installs don't break. Same deferral.

These are tracked in the project issue tracker as `m9-followup`.

## 5. Final pre-ship checklist

- [ ] M9-A cosmetic rebrand merged (logger subsystems, dispatch labels, display strings)
- [ ] M9-B docs merged (README, CONTRIBUTING, NOTICE)
- [ ] IsleHooks + IsleSetup build green via `swift build -c release`
- [ ] Xcode Run Script phase added (this doc, §1)
- [ ] `xcodebuild -scheme DynamicIsland -configuration Release` builds clean
- [ ] Launch the built app, open Settings → Coding Agents → Install Claude Code hooks → verify `~/.claude/settings.json` is modified with `IsleHooks` command path
- [ ] Trigger a Claude Code session → verify session appears in the Agents tab within 5 s
- [ ] All Atoll's existing media features still work (Music, Spotify, **Podcasts**)
