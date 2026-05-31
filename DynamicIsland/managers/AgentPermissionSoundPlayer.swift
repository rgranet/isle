/*
 * Isle (built on Atoll / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 * GPL v3 — see LICENSE.
 */

import AVFoundation
import Defaults
import Foundation

/// Plays a short audio cue when a coding agent requests user attention.
/// Reuses the `audio-feedback.m4a` already bundled with Atoll so we don't
/// ship an extra resource. Sound is gated on `Defaults[.codingAgentsSoundEnabled]`.
@MainActor
final class AgentPermissionSoundPlayer {
    static let shared = AgentPermissionSoundPlayer()

    private var player: AVAudioPlayer?
    private var lastPlayedAt: Date = .distantPast
    private let cooldown: TimeInterval = 1.5

    private init() {
        guard let url = Bundle.main.url(forResource: "audio-feedback", withExtension: "m4a") else {
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.volume = 0.35
    }

    /// Play once. Self-throttled so back-to-back permission events
    /// (rare but possible: two hooks firing in the same tick) don't
    /// cause overlapping clicks.
    func playAttentionCue() {
        guard Defaults[.codingAgentsSoundEnabled] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayedAt) >= cooldown else { return }
        lastPlayedAt = now

        player?.currentTime = 0
        player?.play()
    }
}
