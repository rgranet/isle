/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Defaults
import SwiftUI

/// Floating dock: a detached capsule of tab buttons hovering
/// below the open notch panel, plus a separate circular settings button.
/// Replaces the in-panel tab bar when `Defaults[.enableNotchDock]` is on.
///
/// The view includes an invisible strip covering the gap between the panel
/// and the capsules so the cursor never crosses a dead hover zone; the
/// parent (ContentView) uses `onHoverChange` to suppress auto-close while
/// the dock is hovered and to close the notch when the cursor leaves it.
/// The notch silhouette extended with the dock strip below it. Used as the
/// panel's `.contentShape` while the dock is visible, so hover/click hit
/// testing treats the dock area as part of the notch (paths may extend
/// beyond the view's bounds — SwiftUI honors them for hit testing).
struct NotchWithDockHoverShape: Shape {
    let base: AnyShape

    func path(in rect: CGRect) -> Path {
        var path = base.path(in: rect)
        path.addRect(CGRect(
            x: rect.minX,
            y: rect.maxY,
            width: rect.width,
            height: notchDockGap + notchDockHeight + notchDockBottomClearance
        ))
        return path
    }
}

struct NotchDockView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared

    // Reactivity: the tab list itself is built by NotchTabCatalog; these
    // keep the dock re-rendering when the feature flags change.
    @Default(.enableCodingAgents) private var enableCodingAgents
    @Default(.enableNotchWeather) private var enableNotchWeather
    @Default(.enableMessagingApps) private var enableMessagingApps
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.enableStatsFeature) private var enableStatsFeature
    @Default(.enableNotes) private var enableNotes
    @Default(.enableTerminalFeature) private var enableTerminalFeature
    @Default(.dynamicShelf) private var dynamicShelf
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.settingsIconInNotch) private var settingsIconInNotch

    @Namespace private var dockAnimation

    private var tabs: [TabModel] {
        NotchTabCatalog.tabs()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hover bridge over the gap between the panel and the capsules.
            Color.clear
                .frame(height: notchDockGap)

            HStack(spacing: 10) {
                if !tabs.isEmpty {
                    tabCapsule
                }
                if settingsIconInNotch {
                    settingsButton
                }
            }
            .frame(height: notchDockHeight)
        }
        .fixedSize()
        .onAppear {
            ensureValidSelection()
        }
    }

    private var tabCapsule: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                dockButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: notchDockHeight)
        .background(dockSurface(in: Capsule(style: .continuous)))
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
    }

    private func dockButton(for tab: TabModel) -> some View {
        let selected = isSelected(tab)
        let accent = tab.accentColor ?? Color.effectiveAccent

        return Button {
            if tab.view == .extensionExperience {
                coordinator.selectedExtensionExperienceID = tab.experienceID
            }
            coordinator.currentView = tab.view
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                .frame(width: 34, height: notchDockHeight - 10)
                .background {
                    // Same placeholder trick as TabSelectionView so the
                    // selection pill slides between buttons.
                    if selected {
                        Capsule()
                            .fill(accent.opacity(0.35))
                            .shadow(color: accent.opacity(0.5), radius: 6)
                            .matchedGeometryEffect(id: "dockCapsule", in: dockAnimation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "dockCapsule", in: dockAnimation)
                            .hidden()
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }

    private var settingsButton: some View {
        Button {
            SettingsWindowController.shared.showWindow()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: notchDockHeight, height: notchDockHeight)
                .background(dockSurface(in: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    /// Shared smoked-glass chrome for the dock surfaces.
    private func dockSurface<S: InsettableShape>(in shape: S) -> some View {
        shape
            .fill(Color.black.opacity(0.82))
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    /// Same guard as TabSelectionView: if the current view's tab is gone
    /// (feature disabled), fall back to the first available tab.
    private func ensureValidSelection() {
        let tabs = self.tabs
        guard !tabs.isEmpty, !tabs.contains(where: { isSelected($0) }) else { return }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}
