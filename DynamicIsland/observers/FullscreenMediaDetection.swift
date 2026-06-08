/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import MacroVisionKit
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: MacroVisionKit
    @ObservedObject private var musicManager = MusicManager.shared
    @MainActor @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?

    private init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
        updateFullScreenStatus()
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    
                    for await _ in activeSpaceNotifications {
                        await self?.handleChange()
                    }
                }
                
                group.addTask {
                    let screenParameterNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named:  NSApplication.didChangeScreenParametersNotification
                    )
                    
                    for await _ in screenParameterNotifications {
                        await  self?.handleChange()
                    }
                }
            }
        }
    }

    private func handleChange() async {
        try? await Task.sleep(for: .milliseconds(500))
        self.updateFullScreenStatus()
    }

    private func updateFullScreenStatus() {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }
        

        let apps = detector.detectFullscreenApps(debug: false).filter { info in
            // MacroVisionKit flags any window that fills the screen's *safe
            // area* (frame minus insets) within a 2% tolerance. On a non-notch
            // display that 2% (~25px on a 1440p screen) is larger than the
            // ~24px menu bar, so an ordinary *maximized* window — whose top
            // stops just below the menu bar — is misreported as fullscreen and
            // the pill hides on the plain desktop. A true native-fullscreen
            // window covers the entire screen frame (the menu-bar strip too);
            // a maximized window does not. Require a full-frame match to tell
            // them apart. (Harmless on notch Macs: there the notch screen is
            // never hidden by this path anyway.)
            let screenSize = info.screen.frame.size
            let windowSize = info.windowFrame.size
            return abs(windowSize.width - screenSize.width) < 2
                && abs(windowSize.height - screenSize.height) < 2
        }
        let names = NSScreen.screens.map { $0.localizedName }
        var newStatus: [String: Bool] = [:]
        for name in names {
            newStatus[name] = apps.contains { $0.screen.localizedName == name && $0.bundleIdentifier != "com.apple.finder" && ($0.bundleIdentifier == musicManager.bundleIdentifier || Defaults[.hideNotchOption] == .always) }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
