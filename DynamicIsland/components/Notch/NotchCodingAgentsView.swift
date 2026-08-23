/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version. See LICENSE.
 */

import AppKit
import Defaults
import IsleCore
import SwiftUI

/// Notch tab listing currently-active local coding-agent sessions.
///
/// In M3 only Claude Code is implemented (discovered via transcript scans).
/// Codex (M4), OpenCode (M5), and the rest plug into `AgentSessionStore`.
struct NotchCodingAgentsView: View {
    @ObservedObject private var store = AgentSessionStore.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.enableCodingAgents) private var enableCodingAgents

    // `pendingPermission` is intentionally NOT a @State here anymore.
    // The floating AgentPermissionSheet was removed in favor of the
    // inline Yes / No buttons rendered inside each session card. The
    // AgentPermissionSheet view stays in the project as a fallback
    // (and is still referenced by AgentPermissionPresenter, which is
    // also disabled at launch).
    @State private var scrollSuppressionToken = UUID()
    @State private var autoCloseSuppressionToken = UUID()
    @State private var isSuppressing = false

    /// Only sessions that are actually doing something right now.
    ///
    /// Drops post-hoc transcript sessions read off disk that are already
    /// `.completed` — those are historical artifacts, not actionable.
    /// We keep:
    ///   • sessions currently waiting on user input (permission / question)
    ///   • hook-managed sessions whose `SessionEnd` event hasn't arrived
    ///   • running Codex.app sessions (live process)
    private var activeSessions: [AgentSession] {
        store.sessions.filter { session in
            if session.phase.requiresAttention { return true }
            if session.isHookManaged { return !session.isSessionEnded }
            if session.isCodexAppSession { return session.isProcessAlive }
            if session.isProcessAlive { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if enableCodingAgents {
                header
                Divider().padding(.horizontal, 12)

                if activeSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
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
            store.refreshNow()
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        // Floating-sheet path removed — the in-card inline buttons are
        // the only approval surface now.
    }

    /// Mirrors the suppression pattern used by NotchTerminalView and the
    /// Notes/Clipboard views: while the cursor is anywhere over this tab,
    /// suspend both the scroll-gesture sensor (which would otherwise
    /// interpret a scroll wheel event as a "cursor outside the notch"
    /// signal) and the generic auto-close hover detector. Without this the
    /// notch closes mid-scroll on long agent lists.
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
        vm.setAutoCloseSuppression(hovering, token: autoCloseSuppressionToken)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))

            Text("Coding agents")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if !activeSessions.isEmpty {
                Text("\(activeSessions.count) active")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Button {
                store.refreshNow()
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

    // MARK: Session list

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(activeSessions) { session in
                    AgentSessionRow(
                        session: session,
                        permissionStartedAt: store.permissionStartTimes[session.id]
                    ) {
                        handleTap(on: session)
                    }
                    .contextMenu {
                        Button("Open in terminal") {
                            openInFinder(session)
                        }
                        if let path = session.jumpTarget?.workingDirectory, !path.isEmpty {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: path),
                                ])
                            }
                        }
                    }
                }

                if !store.permissionHistory.isEmpty {
                    historySection
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    // MARK: Resolved history

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                Text("Recent decisions")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(store.permissionHistory.count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 10)

            VStack(spacing: 3) {
                ForEach(store.permissionHistory.prefix(5)) { entry in
                    PermissionHistoryRow(entry: entry)
                }
            }
        }
    }

    // MARK: Empty / disabled

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image("islemascot-sleeping")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 52)
            Text("No active coding sessions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Sessions opened in Claude Code over the last 24h will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Coding agents are disabled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Enable them in Settings → Coding Agents")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func handleTap(on session: AgentSession) {
        // The card body tap always jumps back to the hosting terminal,
        // even when a permission is pending. Approving / denying is done
        // via the inline Yes / No buttons rendered inside the card — we
        // no longer open the floating AgentPermissionSheet from a tap
        // (user feedback: the popup was disruptive and redundant with
        // the in-notch buttons).
        openInFinder(session)
    }

    private func openInFinder(_ session: AgentSession) {
        AgentSessionJumpback.open(session)
    }
}

// MARK: - AgentSessionRow

/// Single session card. Brand-color stripe on the left, workspace + last
/// assistant message in the middle, current tool tag on the right.
private struct AgentSessionRow: View {
    let session: AgentSession
    /// When the current permission request first appeared. Drives the
    /// expiry progress bar. `nil` if no request is active.
    let permissionStartedAt: Date?
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var attentionPulse = false
    @Default(.codingAgentsPermissionTimeoutSeconds) private var permissionTimeoutSeconds

    private var requiresAttention: Bool { session.phase.requiresAttention }
    private var brand: Color { Color(isleHex: session.tool.brandColorHex) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Brand color stripe — left edge accent.
                Color(isleHex: session.tool.brandColorHex)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.tool.shortName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(isleHex: session.tool.brandColorHex))
                            .tracking(0.6)
                            .fixedSize()

                        // Headline mirrors open-vibe-island's `spotlightHeadlineText`:
                        //   "<workspace> (<branch>) · <prompt>"
                        // Falls back gracefully when the worktree branch and the
                        // first user prompt aren't known yet.
                        Text(headlineText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .layoutPriority(1)

                        Spacer(minLength: 4)

                        // Terminal app badge ("Warp", "iTerm", "Terminal", …)
                        // — same trick open-vibe-island uses to tell the user
                        // which app currently hosts the agent.
                        if let terminalBadge = terminalBadgeText {
                            Text(terminalBadge)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
                                .fixedSize()
                        }

                        if let tool = session.currentToolName, !tool.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 8))
                                Text(tool)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                        }
                    }

                    Text(messageText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Inline permission action row — appears only when this
                    // session is waiting on the user. Forwards the decision
                    // straight through the BridgeServer so the hook unblocks.
                    if requiresAttention, let request = session.permissionRequest {
                        attentionActions(for: request)
                            .padding(.top, 3)
                    }

                    // Inline AskUserQuestion rendering — Claude streamed the
                    // exact question text and option labels through its hook
                    // payload, we just surface them as-is. Multiple questions
                    // are rendered stacked.
                    if let prompt = session.questionPrompt {
                        questionPromptView(for: prompt)
                            .padding(.top, 3)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
            .shadow(
                color: requiresAttention ? brand.opacity(attentionPulse ? 0.55 : 0.2) : .clear,
                radius: requiresAttention ? (attentionPulse ? 10 : 4) : 0
            )
            .animation(
                requiresAttention
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: attentionPulse
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onAppear {
            if requiresAttention { attentionPulse = true }
        }
        .onChange(of: requiresAttention) { _, newValue in
            attentionPulse = newValue
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if requiresAttention {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(brand.opacity(attentionPulse ? 0.24 : 0.08))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        if requiresAttention {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(brand.opacity(attentionPulse ? 0.95 : 0.45), lineWidth: attentionPulse ? 2 : 1.2)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        }
    }

    // MARK: Inline permission actions

    @ViewBuilder
    private func attentionActions(for request: PermissionRequest) -> some View {
        let primaryTitle = request.primaryActionTitle.isEmpty ? "Allow Once" : request.primaryActionTitle
        let secondaryTitle = request.secondaryActionTitle.isEmpty ? "Deny" : request.secondaryActionTitle

        VStack(alignment: .leading, spacing: 5) {
            // Expiry progress bar — TimelineView re-evaluates every second
            // so we don't have to manage a Timer. Empties left-to-right;
            // when it hits 0 Claude's own hook timeout has long since
            // expired and the request has likely been auto-denied by the
            // default policy on the agent side.
            if let startedAt = permissionStartedAt, permissionTimeoutSeconds > 0 {
                expiryBar(startedAt: startedAt, total: permissionTimeoutSeconds)
            }

            // Row 1 — base verdict (always present, mirrors Claude's "Yes"/"No")
            HStack(spacing: 6) {
                inlineActionButton(title: secondaryTitle, isPrimary: false) {
                    recordDecision(.denied)
                    resolve(.deny())
                }
                inlineActionButton(title: primaryTitle, isPrimary: true) {
                    recordDecision(.allowed)
                    resolve(.allowOnce())
                }
            }

            // Row 2+ — every rule update Claude proposed (e.g. "Yes and
            // don't ask again for this command", "Yes and allow Bash for
            // this session", etc.). Wraps with FlowLayout so long labels
            // don't get clipped at the notch width.
            if !request.suggestedUpdates.isEmpty {
                AttentionSuggestionsFlow(spacing: 5) {
                    ForEach(Array(request.suggestedUpdates.enumerated()), id: \.offset) { _, update in
                        inlineActionButton(title: update.displayLabel, isPrimary: false) {
                            recordDecision(.allowedWithRule)
                            resolve(.allowOnce(updatedPermissions: [update]))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expiryBar(startedAt: Date, total: TimeInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = max(0, min(1, 1.0 - elapsed / total))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(brand.opacity(0.8))
                        .frame(width: max(0, proxy.size.width * progress))
                }
            }
            .frame(height: 3)
        }
        .frame(height: 3)
        .padding(.bottom, 1)
    }

    @ViewBuilder
    private func inlineActionButton(title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isPrimary ? .semibold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(isPrimary ? brand : Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isPrimary ? Color.clear : Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .foregroundColor(isPrimary ? .white : .white.opacity(0.85))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func resolve(_ resolution: PermissionResolution) {
        AgentHookBridgeManager.shared.resolvePermission(
            sessionID: session.id,
            resolution: resolution
        )
    }

    /// Tag the imminent resolve with the user's verdict so the history
    /// entry that lands once BridgeServer clears the session shows the
    /// right pill (allowed / denied / allowed + rule).
    private func recordDecision(_ decision: PermissionHistoryEntry.Decision) {
        AgentSessionStore.shared.recordUserDecision(decision, for: session.id)
    }

    private var workspaceText: String {
        if let name = session.jumpTarget?.workspaceName, !name.isEmpty {
            return name
        }
        if !session.title.isEmpty, session.title != session.tool.displayName {
            // ClaudeTranscriptDiscovery sets `title = "Claude · <workspace>"`.
            return session.title.replacingOccurrences(of: "Claude · ", with: "")
        }
        return String(session.id.prefix(8))
    }

    /// Mirrors open-vibe-island's `spotlightHeadlineText`:
    ///   "<workspace> (<branch>) · <first user prompt>"
    /// All segments are optional — falls back to just the workspace when
    /// we don't know the branch or there's no recorded prompt yet.
    private var headlineText: String {
        var headline = workspaceText
        if let branch = session.claudeMetadata?.worktreeBranch, !branch.isEmpty {
            headline += " (\(branch))"
        }
        if let prompt = session.initialUserPromptText?.singleLineTrimmed, !prompt.isEmpty {
            let snippet = prompt.count > 50 ? String(prompt.prefix(48)) + "…" : prompt
            headline += " · \(snippet)"
        }
        return headline
    }

    /// Terminal app pill ("Warp" / "iTerm" / …) — only shown when we
    /// resolved the host terminal via `ActiveAgentProcessDiscovery`.
    /// "Unknown" comes from the transcript-only fallback and isn't worth
    /// surfacing, so we hide it.
    private var terminalBadgeText: String? {
        guard let name = session.jumpTarget?.terminalApp,
              !name.isEmpty,
              name != "Unknown",
              name != "Demo" else { return nil }
        return name
    }

    /// Read-only rendering of a Claude `AskUserQuestion` payload. The
    /// hook gives us the exact wording + option labels, so we surface
    /// them verbatim. The actual answer has to be selected in the
    /// terminal — Claude's interactive picker owns the response side
    /// of that flow, and there is no PreToolUse path to inject it.
    @ViewBuilder
    private func questionPromptView(for prompt: QuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(prompt.questions.enumerated()), id: \.offset) { _, question in
                if !question.question.isEmpty, question.question != prompt.title {
                    Text(question.question)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                    HStack(spacing: 5) {
                        Text("\(idx + 1).")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(brand)
                        Text(option.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            Text("Answer in your terminal.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)
        }
    }

    private var messageText: String {
        if let pending = session.permissionRequest {
            return "Needs approval: \(pending.title)"
        }
        if session.questionPrompt != nil {
            // Question detail renders in its own block; suppress the
            // generic "last assistant message" so we don't show two
            // competing pieces of text.
            return ""
        }
        if let body = session.completionAssistantMessageText, !body.isEmpty {
            return body
        }
        if let prompt = session.latestUserPromptText, !prompt.isEmpty {
            return "› \(prompt)"
        }
        if !session.summary.isEmpty {
            return session.summary
        }
        return "No recent activity"
    }
}

// MARK: - Tiny string helper

private extension String {
    /// Collapses whitespace runs (including newlines) into single spaces
    /// and trims edges. Used so a prompt extracted from a multi-line
    /// JSONL transcript renders cleanly on one row.
    var singleLineTrimmed: String {
        let pattern = #"\s+"#
        let collapsed = self.replacingOccurrences(
            of: pattern, with: " ", options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Compact left-aligned flow layout used by `AgentSessionRow` to wrap the
/// per-suggestion pill buttons when there are more options than fit on a
/// single notch-width row. Keeps each pill at its intrinsic size and
/// flows to the next line when it runs out of horizontal space.
private struct AttentionSuggestionsFlow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                maxRowWidth = max(maxRowWidth, lineWidth - spacing)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        maxRowWidth = max(maxRowWidth, lineWidth - spacing)
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - History row

private struct PermissionHistoryRow: View {
    let entry: PermissionHistoryEntry

    private var brand: Color { Color(isleHex: entry.tool.brandColorHex) }
    private var decisionColor: Color {
        switch entry.decision {
        case .allowed, .allowedWithRule: return .green
        case .denied:                    return .red
        case .unknown:                   return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.decision.systemSymbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(decisionColor)

            Text(entry.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let workspace = entry.workspace, !workspace.isEmpty {
                Text("· \(workspace)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(entry.elapsedShortLabel)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(brand.opacity(0.15), lineWidth: 0.5)
        )
    }
}
