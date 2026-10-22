//
//  LocalRecordingRecorder.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import AVFoundation
import Foundation

/// Captures local audio into rolling `.m4a` file chunks under
/// `Documents/Recordings/`.
///
/// MAP_SDK_LIMITATION: MobileRTC's local-recording APIs
/// (`MobileRTCMeetingService+InMeeting.h`) only let a participant *request*
/// local-recording privilege from the host and manage the on/off state — they
/// do not expose a file handle or raw mixed-audio stream to third-party apps.
/// The closest supported solution is to record the device microphone directly
/// into the app's own Documents folder, which is what this type does.
@MainActor
final class LocalRecordingRecorder: NSObject {
    static let shared = LocalRecordingRecorder()

    private(set) var isRecording = false
    private(set) var isPaused = false
    private var isManuallyPaused = false
    private var isSpeechActive = false
    private var silenceTask: Task<Void, Never>?

    /// Called after a file chunk is finalized or the file list otherwise changes.
    var onFilesChanged: (() -> Void)?

    private var recorder: AVAudioRecorder?
    /// File currently being written — must not be offered for playback.
    private var activeRecordingURL: URL?
    private var chunkTask: Task<Void, Never>?
    private let chunkInterval: TimeInterval = 60
    /// Tiny / unfinished AAC files cannot be opened by AVAudioPlayer.
    private let minimumPlayableBytes = 1_024

    private lazy var directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func start() {
        guard !isRecording else { return }
        isRecording = true
        isManuallyPaused = false
        isSpeechActive = false
        beginChunk()
        applyRecordingState()
    }

    func pause() {
        guard isRecording else { return }
        isManuallyPaused = true
        applyRecordingState()
    }

    func resume() {
        guard isRecording else { return }
        isManuallyPaused = false
        applyRecordingState()
    }

    /// Records only while Zoom reports real voice activity. A short hold keeps
    /// the end of words from being clipped when `isTalking` briefly drops.
    func setSpeechActive(_ active: Bool) {
        guard isRecording else { return }
        silenceTask?.cancel()
        silenceTask = nil

        if active {
            isSpeechActive = true
            applyRecordingState()
        } else {
            silenceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, !Task.isCancelled else { return }
                self.isSpeechActive = false
                self.applyRecordingState()
                self.silenceTask = nil
            }
        }
    }

    func stop() {
        silenceTask?.cancel()
        silenceTask = nil
        chunkTask?.cancel()
        chunkTask = nil
        finalizeCurrentChunk()
        isRecording = false
        isPaused = false
        isManuallyPaused = false
        isSpeechActive = false
    }

    func loadFiles() -> [LocalRecordingFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let activePath = activeRecordingURL?.standardizedFileURL.path
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let oldestAllowed = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        return urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .compactMap { url -> LocalRecordingFile? in
                let standardized = url.standardizedFileURL
                // Still being written — incomplete AAC containers fail to open.
                if let activePath, standardized.path == activePath {
                    return nil
                }
                let values = try? standardized.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let size = values?.fileSize ?? 0
                if size < minimumPlayableBytes {
                    try? fm.removeItem(at: standardized)
                    return nil
                }
                let date = values?.contentModificationDate ?? Date()
                // Only keep recordings from the last 7 calendar days (today inclusive).
                guard date >= oldestAllowed else { return nil }
                return LocalRecordingFile(
                    id: standardized.lastPathComponent,
                    fileName: standardized.deletingPathExtension().lastPathComponent,
                    dateGroup: dayFormatter.string(from: date),
                    sizeText: Self.formattedSize(size),
                    createdAt: date,
                    url: standardized
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ file: LocalRecordingFile) {
        try? FileManager.default.removeItem(at: file.url)
        onFilesChanged?()
    }

    func deleteAll() {
        for file in loadFiles() {
            try? FileManager.default.removeItem(at: file.url)
        }
        onFilesChanged?()
    }

    // MARK: - Private

    private func applyRecordingState() {
        let shouldPause = isManuallyPaused || !isSpeechActive
        guard shouldPause != isPaused else { return }
        isPaused = shouldPause
        if shouldPause {
            recorder?.pause()
            chunkTask?.cancel()
            chunkTask = nil
        } else {
            recorder?.record()
            scheduleNextChunk()
        }
    }

    private func beginChunk() {
        let url = directory
            .appendingPathComponent(Self.fileName(for: Date()))
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64_000
        ]
        do {
            try prepareAudioSessionForRecording()
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = false
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                try? FileManager.default.removeItem(at: url)
                activeRecordingURL = nil
                recorder = nil
                return
            }
            activeRecordingURL = url
            recorder = newRecorder
        } catch {
            try? FileManager.default.removeItem(at: url)
            activeRecordingURL = nil
            recorder = nil
        }
    }

    private func finalizeCurrentChunk() {
        guard let current = recorder else {
            activeRecordingURL = nil
            return
        }
        current.stop()
        recorder = nil
        // Keep activeRecordingURL until delegate confirms success/failure so
        // loadFiles() never exposes a half-written file mid-stop.
    }

    private func scheduleNextChunk() {
        chunkTask?.cancel()
        chunkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.chunkInterval ?? 60) * 1_000_000_000)
            guard let self, !Task.isCancelled, self.isRecording, !self.isPaused else { return }
            self.finalizeCurrentChunk()
            // Wait briefly for the stop to flush the AAC container before listing.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, self.isRecording, !self.isPaused else { return }
            self.beginChunk()
            self.scheduleNextChunk()
        }
    }

    private func prepareAudioSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setActive(true, options: [])
    }

    private func handleFinishedRecording(url: URL, successfully flag: Bool) {
        if activeRecordingURL?.standardizedFileURL.path == url.standardizedFileURL.path {
            activeRecordingURL = nil
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if !flag || size < minimumPlayableBytes {
            try? FileManager.default.removeItem(at: url)
        }
        onFilesChanged?()
    }

    private static func fileName(for date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "MMM"
        let month = dayFormatter.string(from: date)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        // Avoid `:` in filenames — some players/filesystems mishandle them.
        timeFormatter.dateFormat = "hh-mm-ss_a"
        let time = timeFormatter.string(from: date)
        return "REC__\(day)\(ordinalSuffix(for: day))_\(month)_\(time)"
    }

    private static func ordinalSuffix(for day: Int) -> String {
        switch day % 100 {
        case 11, 12, 13:
            return "th"
        default:
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    private static func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return "\(Int(kb.rounded())) KB"
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

extension LocalRecordingRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in
            self.handleFinishedRecording(url: url, successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor in
            self.handleFinishedRecording(url: url, successfully: false)
        }
    }
}
