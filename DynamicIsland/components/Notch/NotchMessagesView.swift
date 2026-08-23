/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AppKit
import Defaults
import SwiftUI

/// Notch tab listing the messaging apps Isle monitors (WhatsApp, Teams,
/// Slack, iMessage). Each row shows the per-app unread count and a button
/// to bring that app to the foreground.
struct NotchMessagesView: View {
    @ObservedObject private var monitor = MessagingAppMonitor.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.enableMessagingApps) private var enabled

    @State private var scrollSuppressionToken = UUID()
    @State private var autoCloseSuppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        VStack(spacing: 0) {
            if enabled {
                header
                Divider().padding(.horizontal, 12)
                if monitor.unreadCounts.isEmpty {
                    emptyState
                } else {
                    appList
                }
            } else {
                disabledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onAppear {
            monitor.refreshNow()
        }
        .onDisappear {
            updateSuppression(for: false)
        }
    }

    /// Mirror of the suppression dance used by NotchCodingAgentsView so
    /// scrolling inside the tab doesn't trigger the auto-close hover sensor.
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
        vm.setAutoCloseSuppression(hovering, token: autoCloseSuppressionToken)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))

            Text("Messages")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if monitor.totalUnread > 0 {
                Text("\(monitor.totalUnread) unread")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: App list

    private var appList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(monitor.unreadSorted, id: \.app.id) { entry in
                    MessagingAppRow(app: entry.app, unread: entry.count) {
                        monitor.activate(entry.app)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    // MARK: Empty / disabled states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image("islemascot-default")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 52)
            Text("Inbox zero")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("No unread messages in any monitored app.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if !DockBadgeReader.hasAccessibilityPermission {
                accessibilityHint
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Messaging apps are disabled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Enable them in Settings → Messaging Apps")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessibilityHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            Text("Accessibility permission missing")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Grant it in System Settings → Privacy & Security → Accessibility.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Per-app row

private struct MessagingAppRow: View {
    let app: MessagingApp
    let unread: Int
    let onOpen: () -> Void

    @State private var isHovering = false

    private var brand: Color { Color(isleHex: app.brandColorHex) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                ZStack(alignment: .topTrailing) {
                    appIcon
                        .frame(width: 34, height: 34)

                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.35), lineWidth: 0.6)
                        )
                        .offset(x: 7, y: -5)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                }
                .frame(width: 34, height: 34)

                Text(app.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovering ? .secondary : .tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brand.opacity(isHovering ? 0.18 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(brand.opacity(isHovering ? 0.45 : 0.0), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        // Use the user-supplied asset if it exists, otherwise fall back
        // to a brand-color rounded square with the SF Symbol of the app.
        if NSImage(named: app.iconAssetName) != nil {
            Image(app.iconAssetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(brand)
                .overlay(
                    Image(systemName: app.fallbackSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}
