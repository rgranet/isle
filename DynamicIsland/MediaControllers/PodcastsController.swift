/*
 * Isle (built on Isle / DynamicIsland)
 * Copyright (C) 2026 Isle contributors
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version. See LICENSE.
 *
 * Pattern adapted from AppleMusicController.swift (Isle, originally
 * boring.notch). PodcastsController targets Apple Podcasts.app (bundle ID
 * com.apple.podcasts), uses its AppleScript dictionary for transport
 * commands, and falls back to the iTunes Search API for cover art when
 * the local artwork blob is unavailable.
 */

import AppKit
import Combine
import Foundation

private struct ITunesPodcastResponse: Decodable {
    let results: [ITunesPodcastResult]
}

private struct ITunesPodcastResult: Decodable {
    let trackName: String?        // episode name when entity=podcastEpisode
    let collectionName: String?   // show name
    let artworkUrl600: String?
    let artworkUrl100: String?
}

class PodcastsController: MediaControllerProtocol {
    static let bundleIdentifier = "com.apple.podcasts"

    // MARK: - Properties

    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: PodcastsController.bundleIdentifier,
        playbackRate: 1
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool { true }

    private static let minimumArtworkSize = 16

    private var pollTimer: Timer?
    private var lastCatalogArtworkKey: String?
    private var cachedCatalogArtwork: Data?

    // MARK: - Init

    init() {
        startPollingIfActive()
    }

    deinit {
        pollTimer?.invalidate()
    }

    /// Apple Podcasts does not post a public distributed notification on
    /// playback-state changes (unlike Music's `com.apple.Music.playerInfo`).
    /// We poll every 2s while Podcasts.app is running. Cheap because the
    /// AppleScript call is fast and only runs when the app is foregrounded.
    private func startPollingIfActive() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive() else { return }
            Task { [weak self] in
                await self?.updatePlaybackInfo()
            }
        }
    }

    // MARK: - Protocol implementation

    func play() async {
        await executeCommand("play")
    }

    func pause() async {
        await executeCommand("pause")
    }

    func togglePlay() async {
        await executeCommand("playpause")
    }

    func nextTrack() async {
        // Modern Podcasts.app exposes `skip forward` for ±15s skips and
        // `play next` to advance to the next episode in the queue.
        await executeCommand("play next")
    }

    func previousTrack() async {
        await executeCommand("play previous")
    }

    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }

    /// Podcasts has no native shuffle concept. No-op rather than crashing.
    func toggleShuffle() async {}

    /// Podcasts has no native repeat concept either.
    func toggleRepeat() async {}

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == Self.bundleIdentifier }
    }

    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 6 else { return }

        var updatedState = self.playbackState
        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        // Map "show" → artist slot and "episode" → title so the existing
        // music UI surfaces sensible labels without per-controller checks.
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0

        if let artData = descriptor.atIndex(7)?.data as Data?,
           artData.count > Self.minimumArtworkSize {
            updatedState.artwork = artData
        } else {
            updatedState.artwork = await fetchArtworkFromCatalog(
                episode: updatedState.title,
                show: updatedState.artist
            )
        }

        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }

    // MARK: - Private

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        // `current track` is the cross-version-safe accessor that modern
        // Podcasts.app exposes. The dictionary varies slightly per macOS
        // release, hence the broad on-error fallback.
        let script = """
        tell application "Podcasts"
            try
                set playerState to player state is playing
                set episodeTitle to name of current track
                set showName to artist of current track
                set podcastAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set artData to ""
                try
                    set artData to raw data of artwork 1 of current track
                end try
                return {playerState, episodeTitle, showName, podcastAlbum, trackPosition, trackDuration, artData}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, ""}
            end try
        end tell
        """
        return try await AppleScriptHelper.execute(script)
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Podcasts\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func fetchArtworkFromCatalog(episode: String, show: String) async -> Data? {
        let key = "\(episode)|\(show)"
        if key == lastCatalogArtworkKey, let cached = cachedCatalogArtwork {
            return cached
        }

        let query = "\(show) \(episode)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=podcast&entity=podcastEpisode&limit=10")
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesPodcastResponse.self, from: data)
            guard !response.results.isEmpty else { return nil }

            let normalizedShow = show.lowercased()
            let normalizedEpisode = episode.lowercased()
            let match = response.results.first(where: {
                $0.trackName?.lowercased() == normalizedEpisode &&
                $0.collectionName?.lowercased() == normalizedShow
            }) ?? response.results.first(where: {
                $0.collectionName?.lowercased() == normalizedShow
            }) ?? response.results.first

            // Prefer 600px artwork; fall back to upscaling the 100px URL.
            let urlString = match?.artworkUrl600
                ?? match?.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600")
            guard let urlString, let imageURL = URL(string: urlString) else { return nil }

            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            lastCatalogArtworkKey = key
            cachedCatalogArtwork = imageData
            return imageData
        } catch {
            return nil
        }
    }
}
