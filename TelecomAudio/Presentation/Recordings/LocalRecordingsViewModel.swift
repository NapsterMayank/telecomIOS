//
//  SpeakerRouteOption.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

/// A selectable audio output destination in the Speaker bottom sheet.
enum SpeakerRouteOption: String, CaseIterable, Identifiable {
    case iPhoneSpeaker
    case receiver
    case airPods
    case bluetooth
    case wiredEarphones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhoneSpeaker: return "iPhone Speaker"
        case .receiver: return "Receiver"
        case .airPods: return "AirPods"
        case .bluetooth: return "Bluetooth Device"
        case .wiredEarphones: return "Wired Earphones"
        }
    }

    var icon: String {
        switch self {
        case .iPhoneSpeaker: return "speaker.wave.2.fill"
        case .receiver: return "phone.fill"
        case .airPods: return "airpodspro"
        case .bluetooth: return "headphones"
        case .wiredEarphones: return "cable.connector"
        }
    }
}

/// Drives the participant's real-time Zoom meeting screen (Android reference:
/// `Book` session card + network/mic/recording status + Leave/Speaker/
/// Recordings + big mic). Pause/Resume is in Settings; auto-pauses on
/// background / phone calls and resumes on return.
///
/// This is the live participant experience: mute, pause/resume, network
/// quality, and meeting status are all driven by `AudioMeetingServiceProtocol`
/// (backed by the real Zoom SDK once `ZOOM_MEETING_SDK` is enabled). Local
/// recordings are real files captured by `LocalRecordingRecorder` — see that
/// type for why files (not raw Zoom SDK access) are the closest supported
/// local-recording solution.
@MainActor
final class LocalRecordingsViewModel: ObservableObject {
    @Published var isMuted: Bool
    @Published var isSpeakerOn: Bool
    @Published var isEarphoneMode: Bool
    @Published var isPaused: Bool
    @Published var isPushToTalkActive = false
    @Published var connectionState: MeetingConnectionState
    @Published var networkQuality: NetworkQuality
    @Published var hostNetworkQuality: NetworkQuality = .unknown
    @Published private(set) var isExternalOutputConnected = false
    @Published private(set) var sessionTitle: String
    @Published private(set) var sessionUsername: String

    /// Participant listening volume only — never affects the mic/send side.
    @Published var volume: Double = 0.7
    @Published var showRecordings = false
    @Published var showSettings = false
    @Published var showLeaveConfirmation = false
    @Published var showMeetingRecordingNotice = false
    @Published var isDisconnecting = false
    @Published var recordings: [LocalRecordingFile] = []
    @Published var recordingPendingDeletion: LocalRecordingFile?
    @Published var showDeleteAllConfirmation = false
    @Published var showHostStatusPopup = false
    /// Red status strip text. `nil` / empty = hidden. Only cleared via X tap;
    /// a new host message replaces this string in place.
    @Published private(set) var hostStatusMessage = ""
    @Published private(set) var hostAvatarURL: URL?
    @Published private(set) var sessionProfileImage: UIImage?
    @Published var showListeningOnByHost = false
    /// `true` = "Listening Off by Host" (Unlisten); `false` = "Listening On by Host".
    @Published private(set) var listeningByHostIsOff = false
    /// When set, banner progress drains until this date (TimelineView; no step blink).
    @Published private(set) var listeningBannerEndsAt: Date?
    /// Android pill over the red X: "Resume meeting to speak".
    @Published private(set) var showResumeToSpeakHint = false
    /// Mic-linked status pill: Recording… / Stopping in Ns / hidden (UI only).
    @Published private(set) var micRecordingPill: MicRecordingPillState = .hidden

    enum MicRecordingPillState: Equatable {
        case hidden
        case recording
        case stopping(secondsLeft: Int)
    }

    @Published private(set) var sessionOwnerName: String
    let sessionMessage: String
    let sessionProfileImageURL: URL?
    let settings: LocalMeetingSettingsStore

    /// Book owner from zoom-token `userMap` — preferred over Zoom tile name.
    private let hostBookOwnerName: String?
    let banner: String?

    private let meetingService: AudioMeetingServiceProtocol
    private let authRepository: AuthRepositoryProtocol
    private let sessionManager: SessionManaging
    private let deviceInfo: DeviceInfoProvider
    private let router: AppRouter
    private let recorder: LocalRecordingRecorder
    private let playbackController = LocalRecordingPlaybackController()
    private var cancellables = Set<AnyCancellable>()
    private var reconnectTask: Task<Void, Never>?
    private var listeningOnTask: Task<Void, Never>?
    private var resumeHintTask: Task<Void, Never>?
    private var micRecordingStopTask: Task<Void, Never>?
    /// Debounce duplicate LISTEN_ALL + "listen" chat deliveries.
    private var lastListenAllAt: Date?
    /// Debounce Unlisten/Listen chat aliases so the banner doesn't restart/blink.
    private var lastForcedPauseAt: Date?
    private var lastForcedPauseValue: Bool?
    /// Auto-pause from background / phone call — resume only when this is set.
    private var pausedByLifecycle = false
    /// Host Unlisten is active — lifecycle resume must not override it.
    private var isForcedPausedByHost = false
    private var lifecycleObserversStarted = false
    /// Prevents duplicate home navigation when the SDK fires `.ended` after logout-all.
    private var loggedOutByHost = false
    private var hostUnavailableHandled = false
    private var hasShownMeetingRecordingNotice = false

    /// Host disconnected / reconnecting — show waiting UI. Zoom `.waitingForHost`
    /// is treated as line switch-off (toast + logout), not this screen.
    var showWaitingScreen: Bool {
        switch connectionState {
        case .connecting, .hostLeft, .reconnecting:
            return true
        case .waitingForHost, .failed, .idle, .preparing, .initializingSDK, .sdkReady, .connected, .ended:
            return false
        }
    }

    static let hostUnavailableMessage = HostJoinAvailability.unavailableMessage

    /// Status pill under HOST: only while mic is live or during stop countdown.
    /// Hidden when idle/muted/paused — no "Stopped" bar on Resume.
    var showRecordingStatusPill: Bool {
        switch micRecordingPill {
        case .hidden: return false
        case .recording, .stopping: return true
        }
    }

    var recordingStatusText: String {
        switch micRecordingPill {
        case .recording:
            return "Recording..."
        case .stopping(let seconds):
            return "Stopping in \(seconds)s"
        case .hidden:
            return ""
        }
    }

    var isMicRecordingPillActive: Bool {
        switch micRecordingPill {
        case .recording, .stopping: return true
        case .hidden: return false
        }
    }

    var isMicRecordingStopping: Bool {
        if case .stopping = micRecordingPill { return true }
        return false
    }

    var meetingStatusText: String {
        switch connectionState {
        case .connected:
            return "Meeting Connected"
        case .reconnecting:
            return "Meeting Reconnecting"
        case .waitingForHost:
            return "Waiting for Host"
        case .hostLeft:
            return "Host Left"
        case .ended:
            return "Meeting Ended"
        case .failed:
            return "Meeting Disconnected"
        case .idle, .preparing, .initializingSDK, .sdkReady, .connecting:
            return "Connecting..."
        }
    }

    /// Whether the big mic button responds to push-to-talk while not paused.
    var canUsePushToTalk: Bool {
        !isPaused
    }

    /// Pause/Resume button shows "Resume" when the participant self-paused.
    var showsResumeButton: Bool {
        isPaused
    }

    /// Pause = maroon, Resume (self-paused) = green.
    var pauseResumeButtonColor: Color {
        isPaused ? AppColors.speakerGreen : AppColors.pauseWine
    }

    /// Small live-mic indicator dot shown on the big mic button while talking.
    /// Unmute with Indicator is hidden in Settings for now — keep always false.
    var showsUnmuteIndicatorDot: Bool {
        // settings.unmuteWithIndicator && isPushToTalkActive
        false
    }

    var groupedRecordings: [(dateGroup: String, files: [LocalRecordingFile])] {
        LocalRecordingFile.grouped(from: recordings)
    }

    var recordingPlayback: LocalRecordingPlaybackController { playbackController }

    var accessToken: String? { sessionManager.accessToken }

    init(
        credentials: ZoomMeetingCredentials?,
        meetingService: AudioMeetingServiceProtocol,
        authRepository: AuthRepositoryProtocol,
        sessionManager: SessionManaging,
        deviceInfo: DeviceInfoProvider,
        router: AppRouter,
        settings: LocalMeetingSettingsStore? = nil,
        recorder: LocalRecordingRecorder? = nil
    ) {
        self.meetingService = meetingService
        self.authRepository = authRepository
        self.sessionManager = sessionManager
        self.deviceInfo = deviceInfo
        self.router = router
        self.settings = settings ?? LocalMeetingSettingsStore()
        self.recorder = recorder ?? .shared

        isMuted = meetingService.isMuted
        isSpeakerOn = meetingService.isSpeakerOn
        isEarphoneMode = meetingService.isEarphoneMode
        isPaused = meetingService.isLocalAudioPaused
        connectionState = meetingService.connectionState
        networkQuality = meetingService.networkQuality
        hostNetworkQuality = meetingService.hostNetworkQuality

        hostBookOwnerName = credentials?.bookName ?? credentials?.bookOwnerName
        banner = credentials?.banner
        sessionOwnerName = Self.sanitizedOwnerName(
            credentials?.bookName ?? credentials?.bookOwnerName ?? credentials?.displayName
        )
        
        let clientMessage = credentials?.clientMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sessionTitle = clientMessage
        sessionUsername = ""
        sessionMessage = "No message available"
        sessionProfileImageURL = credentials?.profileImageURL

        bindService()
        bindRecorder()
        if let profileURL = sessionProfileImageURL {
            Task { await loadSessionProfileImage(from: profileURL) }
        }
        if connectionState == .waitingForHost {
            handleHostUnavailableAndLogout()
        }
        settings?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        playbackController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        observeAudioRoute()
        self.recorder.start()
        self.recorder.setSpeechActive(!meetingService.speakingParticipantIDs.isEmpty)
        loadRecordings()
        if connectionState == .connected {
            presentMeetingRecordingNoticeIfNeeded()
        }
    }

    func onScreenAppear() {
        Task { await meetingService.suppressNativeMeetingUI() }
    }

    func dismissMeetingRecordingNotice() {
        showMeetingRecordingNotice = false
    }

    private func presentMeetingRecordingNoticeIfNeeded() {
        guard !hasShownMeetingRecordingNotice else { return }
        guard recorder.isRecording else { return }
        guard connectionState == .connected, !showWaitingScreen else { return }
        hasShownMeetingRecordingNotice = true
        showMeetingRecordingNotice = true
    }

    private func loadSessionProfileImage(from url: URL) async {
        guard let image = await ProfileImageLoader.load(
            url: url,
            sessionManager: sessionManager,
            deviceInfo: deviceInfo
        ) else { return }
        sessionProfileImage = image
    }

    private func bindService() {
        meetingService.onMuteChange = { [weak self] muted in
            guard let self else { return }
            // PTT mode only: force remute if SDK unmuted without a hold.
            // Unmute-with-touch mode keeps the unmuted state until the next tap.
            if !muted, !self.isPushToTalkActive, !self.isPaused, !self.settings.unmuteWithTouch {
                Task { await self.meetingService.setMuted(true) }
                self.isMuted = true
                return
            }
            self.isMuted = muted
            if self.settings.unmuteWithTouch {
                let live = !muted && !self.isPaused
                self.isPushToTalkActive = live
                self.applyMicRecordingPill(isMicLive: live)
            }
        }
        meetingService.onAudioRouteChange = { [weak self] speaker, earphone in
            self?.isSpeakerOn = speaker
            self?.isEarphoneMode = earphone
        }
        meetingService.onParticipantsChange = { [weak self] participants in
            guard let self else { return }
            guard self.hostBookOwnerName == nil else { return }
            if let hostName = participants.first(where: \.isHost)?.name {
                let cleaned = Self.sanitizedOwnerName(hostName)
                if !cleaned.isEmpty, cleaned != "Participant", cleaned.lowercased() != "host" {
                    self.sessionOwnerName = cleaned
                }
            }
        }
        meetingService.onStateChange = { [weak self] state in
            guard let self else { return }
            self.connectionState = state
            switch state {
            case .ended:
                self.recorder.stop()
                self.showMeetingRecordingNotice = false
                if !self.loggedOutByHost, !self.isDisconnecting {
                    Task {
                        await self.disconnectAndGoHome {}
                    }
                }
            case .failed:
                // Don't surface an error — retry quietly like a "waiting for host" hiccup.
                self.scheduleAutoRetry()
            case .waitingForHost:
                self.handleHostUnavailableAndLogout()
                self.showMeetingRecordingNotice = false
            case .connecting, .hostLeft, .reconnecting:
                self.showMeetingRecordingNotice = false
            default:
                if state == .connected {
                    self.loggedOutByHost = false
                    self.presentMeetingRecordingNoticeIfNeeded()
                }
                self.reconnectTask?.cancel()
            }
        }
        meetingService.onNetworkQualityChange = { [weak self] quality in
            self?.networkQuality = quality
        }
        meetingService.onHostNetworkQualityChange = { [weak self] quality in
            self?.hostNetworkQuality = quality
        }
        meetingService.onHostAvatarChange = { [weak self] url in
            self?.hostAvatarURL = url
        }
        meetingService.onSpeakingParticipantsChange = { [weak self] ids in
            self?.recorder.setSpeechActive(!ids.isEmpty)
        }
        meetingService.onHostUnavailable = { [weak self] in
            self?.handleHostUnavailableAndLogout()
        }
        meetingService.onHostStatusReceived = { [weak self] message in
            guard let self, !Self.isLogoutStatusMessage(message) else { return }
            if Self.isRemoveStatusMessage(message) {
                self.hostStatusMessage = ""
                self.showHostStatusPopup = false
                return
            }
            let trimmed = Self.displayableStatusMessage(message)
            guard !trimmed.isEmpty else {
                // Empty payload from host clear-status.
                self.hostStatusMessage = ""
                self.showHostStatusPopup = false
                return
            }
            if Self.isRemoveStatusMessage(trimmed) {
                self.hostStatusMessage = ""
                self.showHostStatusPopup = false
                return
            }
            // Replace any previous text; do not auto-dismiss.
            self.hostStatusMessage = trimmed
            self.showHostStatusPopup = false
        }
        meetingService.onListenAllReceived = { [weak self] in
            self?.applyListenAllFromHost()
        }
        meetingService.onLogoutAllReceived = { [weak self] in
            self?.applyLogoutAllFromHost()
        }
        meetingService.onHostForcedListeningPause = { [weak self] paused in
            self?.applyHostForcedListeningPause(paused)
        }
    }

    /// Strips trailing colons some backend usernames include (e.g. `kussu1111::::`).
    private static func sanitizedOwnerName(_ raw: String?) -> String {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Participant"
        }
        while name.hasSuffix(":") {
            name.removeLast()
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Participant" : name
    }

    /// Android may send `addstatusmessage:hi` — banner should show only `hi`.
    private static func displayableStatusMessage(_ message: String) -> String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["addstatusmessage:", "addstatusmessage", "statusmessage:", "status:"]
        for prefix in prefixes {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    /// Host removed the status banner — never show the protocol token as text.
    private static func isRemoveStatusMessage(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        func matches(_ lower: String) -> Bool {
            if lower == "removestatusmessage"
                || lower == "removestatus"
                || lower == "clearstatusmessage"
                || lower == "clearstatus"
                || lower == "deletestatusmessage"
                || lower == "deletestatus" {
                return true
            }
            return lower.hasPrefix("removestatusmessage")
                || lower.hasPrefix("removestatus:")
                || lower.hasPrefix("clearstatusmessage")
                || lower.contains("removestatusmessage")
        }

        if matches(trimmed.lowercased()) { return true }
        return matches(displayableStatusMessage(trimmed).lowercased())
    }

    /// Host has not started the meeting / line is off — toast, cleanup, terminate app.
    private func handleHostUnavailableAndLogout() {
        guard !hostUnavailableHandled, !loggedOutByHost else { return }
        hostUnavailableHandled = true
        loggedOutByHost = true
        reconnectTask?.cancel()
        dismissListeningOnByHost()
        endPushToTalk()
        recorder.stop()
        HostUnavailableExit.handle(
            router: router,
            authRepository: authRepository,
            meetingCleanup: { [self] in
                await meetingService.leaveMeeting()
                await meetingService.deinitialize()
            }
        )
    }

    /// Extra guard so legacy Android hosts that broadcast plain `"logout"` never
    /// surface the Host Status popup even if chat parsing order changes.
    private static func isLogoutStatusMessage(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("logout") == .orderedSame { return true }
        return trimmed.uppercased().contains("LOGOUT_ALL")
    }

    /// Auto-retries a failed/dropped connection (e.g. host disconnected mid-meeting)
    /// without ever showing the user an error screen or popup.
    private func scheduleAutoRetry() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, case .failed = self.connectionState else { return }
            await self.meetingService.refreshConnection()
        }
    }

    private func bindRecorder() {
        recorder.onFilesChanged = { [weak self] in
            self?.loadRecordings()
        }
    }

    /// Detects a connected wired/Bluetooth output purely to flip the top-bar
    /// speaker icon to a headphone glyph — independent of the explicit
    /// speaker-sheet selection, since iOS can switch routes on its own the
    /// moment an accessory connects.
    private func observeAudioRoute() {
        updateExternalOutputFlag()
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in self?.updateExternalOutputFlag() }
            .store(in: &cancellables)
    }

    private func updateExternalOutputFlag() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        isExternalOutputConnected = outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
    }

    private func loadRecordings() {
        recordings = recorder.loadFiles()
    }

    // MARK: - Big mic / push-to-talk / pause

    /// Red X tap while paused — show Android "Resume meeting to speak" hint.
    /// Resume itself is via Settings (not the X).
    func tapBigMicWhilePaused() {
        guard isPaused else { return }
        presentResumeToSpeakHint()
    }

    /// Observe background / phone-call interruptions so listening auto-pauses
    /// and resumes when the user returns (manual Settings pause stays paused).
    func startLifecycleObservers() {
        guard !lifecycleObserversStarted else { return }
        lifecycleObserversStarted = true

        let center = NotificationCenter.default
        center.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)

        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)

        center.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)
    }

    func stopLifecycleObservers() {
        // Publishers live in `cancellables` with other bindings for the meeting
        // lifetime; leaving the screen tears the whole ViewModel down.
        lifecycleObserversStarted = false
    }

    private func handleAppWillResignActive() {
        guard !isPaused else { return }
        pausedByLifecycle = true
        applyPausedState(true, reportToHost: true)
    }

    private func handleAppDidBecomeActive() {
        guard pausedByLifecycle else { return }
        pausedByLifecycle = false
        guard !isForcedPausedByHost else { return }
        applyPausedState(false, reportToHost: true)
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            handleAppWillResignActive()
        case .ended:
            handleAppDidBecomeActive()
        @unknown default:
            break
        }
    }

    func presentResumeToSpeakHint() {
        resumeHintTask?.cancel()
        showResumeToSpeakHint = true
        resumeHintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.showResumeToSpeakHint = false
        }
    }

    func dismissResumeToSpeakHint() {
        resumeHintTask?.cancel()
        resumeHintTask = nil
        showResumeToSpeakHint = false
    }

    /// Hold-to-talk: unmute only while the finger is down (unmute-with-touch OFF).
    func beginPushToTalk() {
        guard !isPaused else {
            presentResumeToSpeakHint()
            return
        }
        guard canUsePushToTalk, !isPushToTalkActive else { return }
        isPushToTalkActive = true
        applyMicRecordingPill(isMicLive: true)
        Task { await meetingService.setMuted(false) }
    }

    /// Release-to-mute: stop sending audio to others.
    func endPushToTalk() {
        guard isPushToTalkActive else { return }
        isPushToTalkActive = false
        applyMicRecordingPill(isMicLive: false)
        Task { await meetingService.setMuted(true) }
    }

    /// Unmute-with-touch ON: single tap toggles mute/unmute (no hold).
    func tapMicForTouchUnmute() {
        guard !isPaused else {
            presentResumeToSpeakHint()
            return
        }
        guard canUsePushToTalk else { return }
        if isPushToTalkActive || !isMuted {
            endPushToTalk()
        } else {
            beginPushToTalk()
        }
    }

    func toggleMute() {
        Task { await meetingService.toggleMute() }
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    /// Settings toggle / manual pause — clears lifecycle auto-resume so a
    /// manual pause is not undone when returning to the app.
    func setPaused(_ paused: Bool) {
        if paused == isPaused { return }
        pausedByLifecycle = false
        if !paused {
            isForcedPausedByHost = false
        }
        applyPausedState(paused, reportToHost: true)
    }

    private func applyPausedState(_ paused: Bool, reportToHost: Bool) {
        if isPushToTalkActive {
            endPushToTalk()
        }
        dismissResumeToSpeakHint()
        isPaused = paused
        if paused {
            clearMicRecordingPill()
            recorder.pause()
        } else {
            recorder.resume()
        }
        Task {
            await meetingService.setLocalAudioPaused(paused)
            if reportToHost {
                await meetingService.reportListeningPaused(paused)
            }
        }
    }

    /// UI-only: "Recording..." while mic is live; "Stopping in Ns" then hide.
    /// Does not start/stop `LocalRecordingRecorder`.
    private func applyMicRecordingPill(isMicLive: Bool) {
        guard !isPaused else { return }
        if isMicLive {
            micRecordingStopTask?.cancel()
            micRecordingStopTask = nil
            micRecordingPill = .recording
            return
        }
        guard case .recording = micRecordingPill else { return }
        beginMicRecordingStopCountdown()
    }

    private func clearMicRecordingPill() {
        micRecordingStopTask?.cancel()
        micRecordingStopTask = nil
        micRecordingPill = .hidden
    }

    private func beginMicRecordingStopCountdown() {
        micRecordingStopTask?.cancel()
        micRecordingStopTask = Task { [weak self] in
            for second in stride(from: 2, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.micRecordingPill = .stopping(secondsLeft: second)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.micRecordingPill = .hidden
            self.micRecordingStopTask = nil
        }
    }

    /// Host tapped Logout All — leave the meeting immediately and return to the
    /// home (Join Meeting) screen. No popup, no waiting screen.
    private func applyLogoutAllFromHost() {
        guard !loggedOutByHost else { return }
        loggedOutByHost = true
        showHostStatusPopup = false
        hostStatusMessage = ""
        reconnectTask?.cancel()
        dismissListeningOnByHost()
        endPushToTalk()
        recorder.stop()
        Task {
            await disconnectAndGoHome {
                await meetingService.leaveMeeting()
                await meetingService.deinitialize()
            }
        }
    }

    /// Host Unlisten → Pause + "Listening Off by Host".
    /// Host Listen → Resume + "Listening On by Host".
    private func applyHostForcedListeningPause(_ paused: Bool) {
        let now = Date()
        // Host broadcasts many aliases (DM + To_All). Re-applying each one
        // restarts the banner / progress and looks like a blink.
        if lastForcedPauseValue == paused,
           let lastForcedPauseAt,
           now.timeIntervalSince(lastForcedPauseAt) < 2.0 {
            return
        }
        lastForcedPauseAt = now
        lastForcedPauseValue = paused

        isForcedPausedByHost = paused
        pausedByLifecycle = false
        applyPausedState(paused, reportToHost: true)
        Task { await meetingService.setMuted(true) }
        if paused {
            presentListeningOffByHost()
        } else {
            presentListeningOnByHost()
        }
    }

    /// Host tapped Listen All — resume listening; banner only if this
    /// participant was paused (matches Android).
    private func applyListenAllFromHost() {
        let now = Date()
        if let lastListenAllAt, now.timeIntervalSince(lastListenAllAt) < 1.5 {
            return
        }
        lastListenAllAt = now

        let wasPaused = isPaused
        isForcedPausedByHost = false
        pausedByLifecycle = false
        applyPausedState(false, reportToHost: true)
        Task { await meetingService.setMuted(true) }
        if wasPaused {
            presentListeningOnByHost()
        }
    }

    func dismissListeningOnByHost() {
        listeningOnTask?.cancel()
        listeningOnTask = nil
        showListeningOnByHost = false
        listeningByHostIsOff = false
        listeningBannerEndsAt = nil
    }

    func dismissHostStatusMessage() {
        hostStatusMessage = ""
        showHostStatusPopup = false
    }

    private func presentListeningOnByHost() {
        presentListeningByHostBanner(isOff: false)
    }

    private func presentListeningOffByHost() {
        presentListeningByHostBanner(isOff: true)
    }

    private static let listeningBannerDuration: TimeInterval = 5

    private func presentListeningByHostBanner(isOff: Bool) {
        // Same banner already up — keep the running countdown (no reset/blink).
        if showListeningOnByHost, listeningByHostIsOff == isOff, listeningOnTask != nil {
            return
        }

        listeningOnTask?.cancel()
        listeningByHostIsOff = isOff
        showListeningOnByHost = true
        let endsAt = Date().addingTimeInterval(Self.listeningBannerDuration)
        listeningBannerEndsAt = endsAt

        listeningOnTask = Task { [weak self] in
            let nanos = UInt64(Self.listeningBannerDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.dismissListeningOnByHost()
        }
    }

    // MARK: - Speaker / Earphone

    /// Android-style toggle: Speaker ↔ Earphone on each tap (no route sheet).
    func toggleSpeakerEarphone() {
        Task {
            if isSpeakerOn && !isEarphoneMode {
                await meetingService.setEarphoneMode(true)
            } else {
                await meetingService.setEarphoneMode(false)
                if !meetingService.isSpeakerOn {
                    await meetingService.toggleSpeaker()
                }
            }
        }
    }

    /// Label/icon for the action button — reflects the *current* route.
    var speakerButtonTitle: String {
        isEarphoneMode || isExternalOutputConnected ? "Earphone" : "Speaker"
    }

    var speakerButtonIcon: String {
        isEarphoneMode || isExternalOutputConnected ? "headphones" : "speaker.wave.2.fill"
    }

    // MARK: - Volume

    func setVolume(_ value: Double) {
        volume = value
        // The actual system-volume write happens via `SystemVolumeBridge`
        // (a hidden MPVolumeView) bound directly to this value in the view.
    }

    // MARK: - Leave

    func requestLeave() {
        showLeaveConfirmation = true
    }

    func cancelLeave() {
        showLeaveConfirmation = false
    }

    func confirmLeave() {
        showLeaveConfirmation = false
        loggedOutByHost = false
        reconnectTask?.cancel()
        dismissListeningOnByHost()
        endPushToTalk()
        recorder.stop()
        Task {
            await disconnectAndGoHome {
                await meetingService.leaveMeeting()
                await meetingService.deinitialize()
            }
        }
    }

    private func disconnectAndGoHome(_ work: () async -> Void) async {
        isDisconnecting = true
        await work()
        try? await Task.sleep(nanoseconds: 900_000_000)
        router.showHome()
    }

    // MARK: - Settings

    func openSettings() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showSettings = true
        }
    }

    func closeSettings() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showSettings = false
        }
    }

    func selectRecordingSystem(_ option: String) {
        settings.recordingSystem = option
    }

    // MARK: - Recordings

    func openRecordings() {
        loadRecordings()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showRecordings = true
        }
    }

    func togglePlayback(_ file: LocalRecordingFile) {
        playbackController.togglePlayback(for: file)
    }

    func isPlaybackActive(_ file: LocalRecordingFile) -> Bool {
        playbackController.isActive(file)
    }

    func isPlaybackPlaying(_ file: LocalRecordingFile) -> Bool {
        playbackController.isActive(file) && playbackController.isPlaying
    }

    func currentTimeText(for file: LocalRecordingFile) -> String? {
        playbackController.formattedCurrentTime(for: file)
    }

    func totalTimeText(for file: LocalRecordingFile) -> String? {
        playbackController.formattedTotalTime(for: file)
    }

    func requestDelete(_ file: LocalRecordingFile) {
        recordingPendingDeletion = file
    }

    func cancelDelete() {
        recordingPendingDeletion = nil
    }

    func confirmDelete() {
        guard let file = recordingPendingDeletion else { return }
        playbackController.stopIfPlaying(file)
        recorder.delete(file)
        recordingPendingDeletion = nil
        loadRecordings()
    }

    func deleteAll() {
        playbackController.stop()
        recorder.deleteAll()
        loadRecordings()
    }

    func requestDeleteAll() {
        showDeleteAllConfirmation = true
    }

    func cancelDeleteAll() {
        showDeleteAllConfirmation = false
    }

    func confirmDeleteAll() {
        showDeleteAllConfirmation = false
        deleteAll()
    }
}
