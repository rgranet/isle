/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Defaults
import Foundation
import SwiftUI

/// One of the messaging apps surfaced in the notch's Messages tab.
///
/// To add a new app:
///   1. Add a case here with its bundle IDs, brand color, icon asset name.
///   2. Drop the matching `<name>icon.imageset` into Assets.xcassets.
///   3. Add a `Defaults.Keys.messagingApp<Name>Enabled` toggle in Constants.swift
///      and surface it in `MessagingApp.enabledDefaultsKey`.
///   4. No other code change needed — UI iterates `MessagingApp.allCases`.
enum MessagingApp: String, CaseIterable, Identifiable, Sendable {
    case whatsapp
    case teams
    case slack
    case imessage
    case discord

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whatsapp: return "WhatsApp"
        case .teams:    return "Microsoft Teams"
        case .slack:    return "Slack"
        case .imessage: return "Messages"
        case .discord:  return "Discord"
        }
    }

    /// Possible bundle identifiers. Several apps ship multiple builds
    /// (Teams Classic vs new Teams; WhatsApp App Store vs DMG) — we
    /// match the first one currently running.
    var bundleIDs: [String] {
        switch self {
        case .whatsapp:
            // App Store build, DMG build, legacy WebApp wrapper.
            return ["net.whatsapp.WhatsApp", "WhatsApp", "desktop.WhatsApp"]
        case .teams:
            // New Teams (2.0+) first, classic as fallback.
            return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .slack:
            return ["com.tinyspeck.slackmacgap"]
        case .imessage:
            // macOS Messages.app — the historical bundle name is MobileSMS.
            return ["com.apple.MobileSMS"]
        case .discord:
            // Stable, PTB (public test build), Canary, Development.
            return [
                "com.hnc.Discord",
                "com.hnc.DiscordPTB",
                "com.hnc.DiscordCanary",
                "com.hnc.DiscordDevelopment",
            ]
        }
    }

    /// The exact string macOS uses as the dock tile title for this app.
    /// `DockBadgeReader` keys badges by this title since AX returns the
    /// display name, not the bundle ID.
    var dockTitle: String {
        switch self {
        case .whatsapp: return "WhatsApp"
        case .teams:    return "Microsoft Teams"
        case .slack:    return "Slack"
        case .imessage: return "Messages"
        case .discord:  return "Discord"
        }
    }

    /// Hex brand color used for the closed-notch indicator dot and the
    /// per-app accent in the Messages tab list.
    var brandColorHex: String {
        switch self {
        case .whatsapp: return "#25D366"   // WhatsApp green
        case .teams:    return "#6264A7"   // Teams purple
        case .slack:    return "#611F69"   // Slack aubergine
        case .imessage: return "#34C759"   // macOS system green
        case .discord:  return "#5865F2"   // Discord blurple
        }
    }

    /// Name of the Image asset in Assets.xcassets. The user drops a
    /// 1024×1024 PNG into the matching imageset; the live activity and
    /// list both look it up by this name. If missing, a brand-colored
    /// pill with the first letter is rendered as fallback.
    var iconAssetName: String {
        switch self {
        case .whatsapp: return "whatsappicon"
        case .teams:    return "teamsicon"
        case .slack:    return "slackicon"
        case .imessage: return "imessageicon"
        case .discord:  return "discordicon"
        }
    }

    /// `Defaults.Keys` boolean toggle for this app's per-app enabled state.
    var enabledDefaultsKey: Defaults.Key<Bool> {
        switch self {
        case .whatsapp: return .messagingAppWhatsAppEnabled
        case .teams:    return .messagingAppTeamsEnabled
        case .slack:    return .messagingAppSlackEnabled
        case .imessage: return .messagingAppIMessageEnabled
        case .discord:  return .messagingAppDiscordEnabled
        }
    }

    /// SF Symbol fallback when no custom icon asset has been shipped yet.
    var fallbackSymbol: String {
        switch self {
        case .whatsapp: return "message.fill"
        case .teams:    return "person.2.fill"
        case .slack:    return "number.square.fill"
        case .imessage: return "bubble.left.and.bubble.right.fill"
        case .discord:  return "gamecontroller.fill"
        }
    }
}
