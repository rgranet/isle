/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AtollExtensionKit
import Defaults
import SwiftUI

/// Single source of truth for the list of notch tabs, shared by the
/// in-panel `TabSelectionView` and the floating `NotchDockView`.
///
/// Callers stay reactive by declaring `@Default` properties for the flags
/// they care about — this builder just reads the current values.
@MainActor
enum NotchTabCatalog {
    static func tabs() -> [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.enableCodingAgents] {
            tabsArray.append(TabModel(label: "Agents", icon: "sparkle", view: .codingAgents))
        }

        if Defaults[.enableNotchWeather] {
            tabsArray.append(TabModel(label: "Weather", icon: "cloud.sun.fill", view: .weather))
        }

        if Defaults[.enableMessagingApps] {
            tabsArray.append(TabModel(label: "Messages", icon: "bubble.left.and.bubble.right.fill", view: .messages))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }

        if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        if Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            tabsArray.append(TabModel(label: label, icon: icon, view: .notes))
        }

        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }

        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }

    static var homeTabVisible: Bool {
        if Defaults[.enableMinimalisticUI] {
            return true
        }
        return Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror]
    }

    private static var extensionTabsEnabled: Bool {
        Defaults[.enableThirdPartyExtensions]
            && Defaults[.enableExtensionNotchExperiences]
            && Defaults[.enableExtensionNotchTabs]
    }

    private static var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        ExtensionNotchExperienceManager.shared.activeExperiences.filter { $0.descriptor.tab != nil }
    }
}
