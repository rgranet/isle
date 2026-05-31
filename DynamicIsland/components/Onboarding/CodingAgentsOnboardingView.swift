/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import Defaults
import LaunchAtLogin
import SwiftUI

/// First-launch introduction screen for the Isle coding-agents integration.
///
/// Acts purely as a master switch — no hook is actually installed here.
/// Hook installation per agent (Claude Code, Codex, etc.) happens later in
/// Settings → Coding Agents, gated by a per-install consent dialog so the
/// user can review which config file will be modified.
struct CodingAgentsOnboardingView: View {
    @Default(.enableCodingAgents) private var enableCodingAgents

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.46, blue: 0.26),
                            Color(red: 0.47, green: 0.36, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 84, height: 84)
                    .blur(radius: 14)
                    .opacity(0.65)

                Image(systemName: "sparkle")
                    .font(.system(size: 56, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 8) {
                Text("Coding agents")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Surface Claude Code, Codex, Cursor, Gemini and other CLI agents directly in the notch — see what they're working on at a glance and approve their permission requests inline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            featureBullets

            VStack(spacing: 10) {
                Toggle(isOn: $enableCodingAgents) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable coding agents")
                            .fontWeight(.medium)
                        Text("You can install per-agent hooks later in Settings → Coding Agents. Nothing is installed yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Isle at login")
                            .fontWeight(.medium)
                        Text("Isle needs to be running for sessions to be tracked live. Recommended.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Button("Set up later") {
                enableCodingAgents = false
                onContinue()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private var featureBullets: some View {
        VStack(alignment: .leading, spacing: 6) {
            bullet(icon: "circle.dotted",
                   text: "Live activity in the notch when an agent is running")
            bullet(icon: "hand.raised.fill",
                   text: "Approve or deny permission requests inline — no terminal switch")
            bullet(icon: "arrow.right.circle.fill",
                   text: "Tap a session to jump back to its terminal window")
            bullet(icon: "lock.fill",
                   text: "Fully local. No telemetry. No account.")
        }
        .padding(.horizontal, 28)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
            Spacer(minLength: 0)
        }
    }
}
