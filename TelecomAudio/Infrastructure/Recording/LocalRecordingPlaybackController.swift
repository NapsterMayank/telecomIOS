//
//  LocalRecordingPlaybackController.swift
//  Learning
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class LocalRecordingPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingFile: LocalRecordingFile?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var lastErrorMessage: String?

    var playingFileID: String? { playingFile?.id }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedTotalTime: String {
        Self.formatTime(duration)
    }

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    func togglePlayback(for file: LocalRecordingFile) {
        if playingFile?.id == file.id {
            togglePlayPause()
            return
        }
        start(file)
    }

    func togglePlayPause() {
        guard playingFile != nil else { return }
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            resume()
        }
    }

    func isActive(_ file: LocalRecordingFile) -> Bool {
        playingFile?.id == file.id
    }

    func formattedCurrentTime(for file: LocalRecordingFile) -> String? {
        guard isActive(file) else { return nil }
        return formattedCurrentTime
    }

    func formattedTotalTime(for file: LocalRecordingFile) -> String? {
        guard isActive(file) else { return nil }
        return formattedTotalTime
    }

    func seek(by delta: TimeInterval) {
        guard let player = audioPlayer else { return }
        let target = min(max(0, player.currentTime + delta), duration)
        player.currentTime = target
        currentTime = target
    }

    func seek(toProgress value: Double) {
        guard let player = audioPlayer, duration > 0 else { return }
        let target = duration * min(1, max(0, value))
        player.currentTime = target
        currentTime = target
    }

    func stopIfPlaying(_ file: LocalRecordingFile) {
        guard isActive(file) else { return }
        stop()
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playingFile = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func start(_ file: LocalRecordingFile) {
        stop()
        lastErrorMessage = nil

        guard FileManager.default.fileExists(atPath: file.url.path) else {
            lastErrorMessage = "Recording file not found."
            return
        }

        let fileSize = (try? file.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard fileSize >= 1_024 else {
            lastErrorMessage = "Recording is incomplete or empty."
            return
        }

        do {
            try prepareAudioSessionForPlayback()
            let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
            player.delegate = self
            guard player.prepareToPlay() else {
                lastErrorMessage = "Unable to prepare this recording."
                return
            }
            audioPlayer = player
            playingFile = file
            duration = player.duration
            currentTime = 0
            isPlaying = player.play()
            if isPlaying {
                startProgressTimer()
            } else {
                lastErrorMessage = "Unable to play this recording."
                stop()
            }
        } catch {
            // Fallback: URL-based open (helps when mapped read is picky).
            do {
                try prepareAudioSessionForPlayback()
                let player = try AVAudioPlayer(contentsOf: file.url)
                player.delegate = self
                guard player.prepareToPlay() else {
                    lastErrorMessage = "Unable to prepare this recording."
                    return
                }
                audioPlayer = player
                playingFile = file
                duration = player.duration
                currentTime = 0
                isPlaying = player.play()
                if isPlaying {
                    startProgressTimer()
                } else {
                    lastErrorMessage = "Unable to play this recording."
                    stop()
                }
            } catch {
                lastErrorMessage = "This recording can’t be played (file may be incomplete)."
            }
        }
    }

    private func prepareAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setActive(true, options: [])
    }

    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        currentTime = audioPlayer?.currentTime ?? currentTime
    }

    private func resume() {
        guard let player = audioPlayer else { return }
        do {
            try prepareAudioSessionForPlayback()
        } catch {
            lastErrorMessage = "Audio session unavailable."
            return
        }
        isPlaying = player.play()
        startProgressTimer()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            currentTime = duration
            isPlaying = false
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
