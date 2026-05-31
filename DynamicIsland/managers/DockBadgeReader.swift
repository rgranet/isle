/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import ApplicationServices
import Foundation

/// Reads the badge labels (e.g. "3", "12+") that other macOS apps render
/// on their Dock tile. macOS has no public API for cross-app notification
/// observation, so we go through the Dock app's Accessibility tree —
/// the same trick Bartender / iStat Menus use.
///
/// **Permissions required**: Accessibility (`Privacy & Security → Accessibility`).
/// Atoll already prompts for this for other features; if Isle doesn't have
/// it, all reads silently return an empty dictionary — the caller will see
/// no unread badges, no crash.
enum DockBadgeReader {
    /// Returns a mapping `[dockTitle: badgeText]` for every dock tile that
    /// currently shows a badge. Polls the live Dock; cheap (<5 ms) so safe
    /// to call every few seconds.
    static func readAllBadges() -> [String: String] {
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
        else {
            return [:]
        }

        let dockApp = AXUIElementCreateApplication(dockPID)

        // The Dock's accessibility tree top-level looks like:
        //   AXApplication "Dock"
        //   └─ AXList "Dock"  (the persistent + open apps row)
        //       └─ AXDockItem * (one per app)
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            dockApp,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        guard let topChildren = childrenRef as? [AXUIElement],
              let dockList = topChildren.first else {
            return [:]
        }

        var itemsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            dockList,
            kAXChildrenAttribute as CFString,
            &itemsRef
        )
        guard let dockItems = itemsRef as? [AXUIElement] else {
            return [:]
        }

        var result: [String: String] = [:]
        for item in dockItems {
            guard let title = stringAttribute(item, kAXTitleAttribute) else {
                continue
            }
            // AXStatusLabel is undocumented but standard on dock tiles for
            // the badge text. It's nil/empty when no badge.
            if let badge = stringAttribute(item, "AXStatusLabel"),
               !badge.isEmpty {
                result[title] = badge
            }
        }
        return result
    }

    /// Whether the running process has Accessibility permission — needed
    /// for the Dock AX queries to return real data. Used by the Settings
    /// pane to show a hint when the toggle is on but nothing is reading.
    ///
    /// We do a **functional** check instead of just `AXIsProcessTrusted()`:
    /// macOS's trust flag can be stale (signed-binary hash mismatch after
    /// a rebuild, TCC database glitch, etc.) and report false even when
    /// the user has correctly ticked the Accessibility box. Actually
    /// trying to read the Dock's children is the ground truth — if we
    /// get a `.success` back, the AX subsystem is letting us in regardless
    /// of what `AXIsProcessTrusted` says.
    static var hasAccessibilityPermission: Bool {
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier else {
            // No Dock → almost impossible on a normal macOS session.
            // Fall back to the cheap trust flag.
            return AXIsProcessTrusted()
        }
        let dockApp = AXUIElementCreateApplication(dockPID)
        var childrenRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            dockApp,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        // .success == we successfully read AX → permission is working
        // .apiDisabled / .cannotComplete / .notImplemented → permission denied
        return err == .success
    }

    /// Diagnostic snapshot for the Settings pane. Splits the two answers
    /// so the user can tell whether AXIsProcessTrusted lies (common after
    /// rebuilds) vs the actual AX query failing (real permission missing).
    static func diagnostic() -> (trusted: Bool, functional: Bool, dockBadgesFound: Int) {
        let trusted = AXIsProcessTrusted()
        let badges = readAllBadges()
        let functional = hasAccessibilityPermission
        return (trusted: trusted, functional: functional, dockBadgesFound: badges.count)
    }

    // MARK: helpers

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &ref
        )
        guard err == .success else { return nil }
        return ref as? String
    }
}
