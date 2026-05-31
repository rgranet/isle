/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import IsleCore
import SwiftUI

/// Modal sheet shown when a coding-agent session is waiting for the user
/// to approve or deny a permission request.
///
/// **M3 status**: UI complete but inert. The buttons surface intent
/// (`.allowOnce`, `.deny`) through the supplied `onDecision` closure; the
/// closure currently just dismisses the sheet. M5 will route real decisions
/// back to the hook subsystem so the agent can resume.
struct AgentPermissionSheet: View {
    let request: PermissionRequest
    let onDecision: (PermissionResolution) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            details
            Divider()
            actions
        }
        .padding(20)
        .frame(width: 420)
        .background(Material.thick)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .font(.system(size: 15, weight: .semibold))
                if let toolName = request.toolName {
                    Text("Requested by tool: \(toolName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !request.summary.isEmpty {
                Text(request.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !request.affectedPath.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(request.affectedPath)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            if !request.suggestedUpdates.isEmpty {
                Text("Suggested rule updates:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                ForEach(Array(request.suggestedUpdates.enumerated()), id: \.offset) { _, update in
                    Text("• \(update.displayLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                onDecision(.deny())
                dismiss()
            } label: {
                Text(request.secondaryActionTitle)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            Button {
                onDecision(.allowOnce())
                dismiss()
            } label: {
                Text(request.primaryActionTitle)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }
}
