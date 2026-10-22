//
//  MeetingViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import AVFoundation
import Foundation
import Combine
import SwiftUI

@MainActor
final class MeetingViewModel: ObservableObject {
    @Published var participants: [MeetingParticipant] = []
    @Published var isMuted = true
    @Published var isSpeakerOn = true
    @Published var isEarphoneMode = false
    @Published var connectionState: MeetingConnectionState = .connected
    @Published var showParticipants = false
    
    /// Ids of participants currently detected as speaking (voice activity).
    @Published private(set) var speakingParticipantIDs: Set<String> = []
    /// Newly joined participants stay yellow briefly (Android join flash).
    @Published private(set) var joiningParticipantIDs: Set<String> = []
    /// Participants who paused listening — host cards show purple.
    @Published private(set) var pausedListeningIDs: Set<String> = []
    /// Participants on handsfree/earphone — host cards show yellow.
    @Published private(set) var handsfreeParticipantIDs: Set<String> = []
    /// Participants who previously had Zoom VoIP connected — used to detect
    /// Android Pause (`pauseCurrentMeeting` → `AudioType_None`).
    private var hadAudioConnectedIDs: Set<String> = []
    /// Remotes that dropped VoIP after being connected — cleared on reconnect
    /// so Android Resume turns the host card green again (iOS already sends chat).
    private var audioDisconnectedIDs: Set<String> = []
    /// After host Unlisten/Listen, suppress participant chat echoes briefly.
    private var hostUnlistenOverrideUntil: [String: Date] = [:]
    @Published private(set) var networkQuality: NetworkQuality = .unknown
    /// Per-participant Zoom audio network quality (Users Network card indicator).
    @Published private(set) var participantNetworkQuality: [String: NetworkQuality] = [:]
    /// After a participant joins and unmutes/speaks, header refresh swaps to host network bars.
    @Published private(set) var showHostNetworkInHeader = false
    /// Host recording banner: Recording... / Stopping in Ns (hidden when stopped).
    /// Driven by participant mic activity (Android), not local recorder state.
    @Published private(set) var recordingBanner: RecordingBannerState = .stopped

    @Published var showFloatingMenu = false
    @Published var showLogoutAllConfirm = false
    @Published var showEndMeetingConfirm = false
    @Published var showLeaveMeetingConfirm = false
    @Published var showRecordings = false
    @Published var showCloudRecordings = false
    @Published var showSettings = false
    @Published var showStatusSheet = false
    @Published var showMeetingRecordingNotice = false
    @Published var statusMessageDraft = ""
    /// Android disconnect screen overlay while leaving / ending.
    @Published var isDisconnecting = false
    /// Red status strip (Android-style). Cleared only via X; new sends replace text.
    @Published private(set) var statusBannerMessage: String?
    @Published var participantMenuTarget: MeetingParticipant?
    @Published private(set) var localHostSessionRole: HostSessionRole?
    @Published private(set) var bothHostAndCoHostPresent = false
    @Published var recordings: [LocalRecordingFile] = []
    @Published var recordingPendingDeletion: LocalRecordingFile?
    @Published var showDeleteAllConfirmation = false

    let expiryDaysText: String
    let expiryDateText: String
    let isHost: Bool
    let meetingTimeLimitMinutes: Int
    @Published var isPaymentPending: Bool
    @Published var meetingRemainingMinutes: Int
    @Published private(set) var meetingLimitEndsAt: Date?
    let settings: HostMeetingSettingsStore
    let cloudRecordings: CloudRecordingsViewModel

    private let meetingService: AudioMeetingServiceProtocol
    private let router: AppRouter
    private let recorder: LocalRecordingRecorder
    private let playbackController = LocalRecordingPlaybackController()
    private var speakingClearTask: Task<Void, Never>?
    private var joiningClearTasks: [String: Task<Void, Never>] = [:]
    private var recordingStopTask: Task<Void, Never>?
    /// Debounces Zoom mute flicker before starting the Stopping countdown.
    private var recordingMuteClearTask: Task<Void, Never>?
    /// Sticky unmuted ids — Zoom briefly flips `isMuted` during talk, which
    /// otherwise blinks Recording ↔ Stopping.
    private var stickyUnmutedIDs: Set<String> = []
    private var unmuteClearTasks: [String: Task<Void, Never>] = [:]
    /// True after a participant mic was live — used to start Stopping countdown.
    private var hadLiveTransmitters = false
    private var knownParticipantIDs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    private var hasShownMeetingRecordingNotice = false

    /// Hold unmuted UI after a mute blip before treating transmitters as gone.
    private static let unmuteHoldNanoseconds: UInt64 = 500_000_000

    enum ParticipantCardState: Equatable {
        case joining
        case idle
        case speaking
        case paused
        case handsfree
    }

    enum RecordingBannerState: Equatable {
        case recording
        case stopping(secondsLeft: Int)
        case stopped

        var title: String {
            switch self {
            case .recording: return "Recording..."
            case .stopping(let seconds): return "Stopping in \(seconds)s"
            case .stopped: return "Stopped"
            }
        }
    }

    var showPaymentPendingBanner: Bool {
        isHost && isPaymentPending
    }

    var paymentPendingMessage: String {
        "Your Zoom account payment is pending. Meeting will work for \(meetingRemainingMinutes) minutes only."
    }

    func displayRemainingMinutes(at date: Date) -> Int {
        let total = TimeInterval(meetingTimeLimitMinutes * 60)
        guard let endsAt = meetingLimitEndsAt, total > 0 else { return meetingRemainingMinutes }
        return max(0, Int(ceil(endsAt.timeIntervalSince(date) / 60)))
    }

    func meetingRemainingRatio(at date: Date = Date()) -> CGFloat {
        let totalSeconds = TimeInterval(meetingTimeLimitMinutes * 60)
        guard totalSeconds > 0 else { return 0 }
        if let endsAt = meetingLimitEndsAt {
            let remaining = endsAt.timeIntervalSince(date)
            return CGFloat(min(1, max(0, remaining / totalSeconds)))
        }
        return CGFloat(meetingRemainingMinutes) / CGFloat(meetingTimeLimitMinutes)
    }

    /// Remote attendees plus the other host-line session (HOST / COHOST card).
    var remoteParticipants: [MeetingParticipant] {
        participants
    }

    var participantCount: Int { remoteParticipants.count }

    var endLeaveButtonTitle: String {
        bothHostAndCoHostPresent ? "Leave" : "End"
    }

    /// Top HOST/COHOST pill — only when someone is in the meeting and actively speaking
    /// (not while alone with "No Participants Connected").
    var localHostSessionBadgeText: String? {
        guard participantCount > 0, !speakingParticipantIDs.isEmpty else { return nil }

        let cohostPeerSpeaking = participants.contains {
            $0.isCohost && speakingParticipantIDs.contains($0.id)
        }
        if cohostPeerSpeaking || (localHostSessionRole == .cohost && isLocalUserSpeaking) {
            return "COHOST"
        }

        let hostPeerSpeaking = participants.contains {
            $0.isHost && !$0.isCohost && speakingParticipantIDs.contains($0.id)
        }
        if hostPeerSpeaking || (localHostSessionRole == .host && isLocalUserSpeaking) {
            return "HOST"
        }

        return nil
    }

    /// Local Zoom user id is not in `participants`; detect self in the speaking set.
    private var isLocalUserSpeaking: Bool {
        speakingParticipantIDs.contains { id in
            !participants.contains(where: { $0.id == id })
        }
    }

    func isHostCoHostPeer(_ participant: MeetingParticipant) -> Bool {
        participant.isHost || participant.isCohost
    }

    func isAttendee(_ participant: MeetingParticipant) -> Bool {
        !isHostCoHostPeer(participant)
    }

    func isHostCoHostSpeaking(_ participant: MeetingParticipant) -> Bool {
        speakingParticipantIDs.contains(participant.id)
    }

    /// Participants ordered for display — unmuted (mic green / transmitting)
    /// pinned to the top when "Users Shuffling" is enabled.
    var displayParticipants: [MeetingParticipant] {
        let base = remoteParticipants
        guard settings.usersShuffling else { return base }
        let transmitting = base.filter { !$0.isMuted }
        guard !transmitting.isEmpty else { return base }
        let idle = base.filter(\.isMuted)
        return transmitting + idle
    }

    /// Participant is connected but the host has not started the meeting yet.
    var isWaitingForHost: Bool {
        !isHost && (connectionState == .waitingForHost || connectionState == .connecting)
    }

    var emptyBannerText: String {
        participantCount == 0 ? "No Participants Connected" : "\(participantCount) Participants Connected"
    }

    var recordingStatusText: String {
        recordingBanner.title
    }

    var isRecordingActive: Bool {
        if case .recording = recordingBanner { return true }
        return false
    }

    /// Hide banner when idle (Android: only while someone is live / stopping).
    var showRecordingStatusBanner: Bool {
        switch recordingBanner {
        case .recording, .stopping: return true
        case .stopped: return false
        }
    }

    var groupedRecordings: [(dateGroup: String, files: [LocalRecordingFile])] {
        LocalRecordingFile.grouped(from: recordings)
    }

    var recordingPlayback: LocalRecordingPlaybackController { playbackController }

    /// Name shown in the black speaking chip. A numeric name is kept as typed.
    var activeSpeakers: [(id: String, name: String)] {
        participants
            .filter { isAttendee($0) && !$0.isMuted }
            .map { participant in
                let parts = Self.participantNameParts(participant.name)
                let name = parts.title.isEmpty ? (parts.username ?? participant.name) : parts.title
                return (id: participant.id, name: name)
            }
    }

    /// Convenience for animations / empty checks.
    var activeSpeakerNames: [String] {
        activeSpeakers.map(\.name)
    }

    /// Host card turns coral when the participant's mic is unmuted (mic tap),
    /// not when Zoom detects voice energy / talking.
    func isSpeaking(_ participant: MeetingParticipant) -> Bool {
        if isHostCoHostPeer(participant) {
            return isHostCoHostSpeaking(participant)
        }
        return !participant.isMuted
    }

    func isJoining(_ participant: MeetingParticipant) -> Bool {
        joiningParticipantIDs.contains(participant.id)
    }

    func isListeningPaused(_ participant: MeetingParticipant) -> Bool {
        if pausedListeningIDs.contains(participant.id) { return true }
        // Android Pause disconnects meeting audio after it was connected.
        if hadAudioConnectedIDs.contains(participant.id), !participant.isAudioConnected {
            return true
        }
        return false
    }

    /// Menu label / toggle — include Android self-pause (audio disconnect).
    /// iOS pause reports via chat into `pausedListeningIDs`; Android often only
    /// drops VoIP (`!isAudioConnected`), which previously left the host on Mute.
    func isUnlistenedByHost(_ participant: MeetingParticipant) -> Bool {
        isListeningPaused(participant)
    }

    func isHandsfree(_ participant: MeetingParticipant) -> Bool {
        handsfreeParticipantIDs.contains(participant.id)
    }

    func cardState(for participant: MeetingParticipant) -> ParticipantCardState {
        if isHostCoHostPeer(participant) {
            if isHostCoHostSpeaking(participant) { return .speaking }
            return .idle
        }
        // Mic unmuted (participant mic tap) → host card coral.
        if isSpeaking(participant) { return .speaking }
        // Pause must win over join-flash / handsfree yellow.
        if isListeningPaused(participant) { return .paused }
        if isJoining(participant) { return .joining }
        if isHandsfree(participant) { return .handsfree }
        return .idle
    }

    func displayName(for participant: MeetingParticipant) -> String {
        if participant.isCohost { return "COHOST" }
        if participant.isHost { return "HOST" }
        return Self.participantNameParts(participant.name).title
    }

    /// Numeric username from `1155::::JOHN`. Nil when the name has no number.
    func username(for participant: MeetingParticipant) -> String? {
        Self.participantNameParts(participant.name).username
    }

    /// Live Zoom network bars for a participant card (Users Network setting).
    func networkQuality(for participant: MeetingParticipant) -> NetworkQuality {
        participantNetworkQuality[participant.id] ?? .unknown
    }

    /// Backend names arrive as `1155::::JOHN` or `kussu1111::::`.
    /// The number is the username; the other part is the card title.
    private static func participantNameParts(_ raw: String) -> (title: String, username: String?) {
        let parts = raw
            .components(separatedBy: "::::")
            .map { segment -> String in
                var piece = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                while piece.hasSuffix(":") { piece.removeLast() }
                return piece.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let username = parts.first { $0.allSatisfy(\.isNumber) }
        let titleSource = parts.last { !$0.allSatisfy(\.isNumber) } ?? parts.last ?? raw
        var title = titleSource.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.hasSuffix(":") { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let separateUsername = title.allSatisfy(\.isNumber) ? nil : username
        if let separateUsername, Self.isDashPlaceholder(title) {
            return (separateUsername, title)
        }
        return (title, separateUsername)
    }

    private static func isDashPlaceholder(_ value: String) -> Bool {
        let trimmed = value.filter { !$0.isWhitespace }
        return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == "–" || $0 == "—" }
    }

    private static func sanitizedParticipantName(_ raw: String) -> String {
        participantNameParts(raw).title
    }

    init(
        credentials: ZoomMeetingCredentials?,
        meetingService: AudioMeetingServiceProtocol,
        router: AppRouter,
        recordingsRepository: RecordingsRepositoryProtocol,
        settings: HostMeetingSettingsStore? = nil,
        recorder: LocalRecordingRecorder? = nil
    ) {
        self.meetingService = meetingService
        self.router = router
        self.isHost = credentials?.isHost ?? true
        self.meetingTimeLimitMinutes = credentials?.meetingTimeLimitMinutes ?? ZoomPaymentStatus.defaultMeetingLimitMinutes
        self.isPaymentPending = credentials?.isPaymentPending ?? false
        self.meetingRemainingMinutes = meetingService.meetingRemainingMinutes
            ?? self.meetingTimeLimitMinutes
        self.settings = settings ?? HostMeetingSettingsStore()
        self.recorder = recorder ?? .shared
        self.cloudRecordings = CloudRecordingsViewModel(repository: recordingsRepository, router: router)

        if let days = credentials?.expiresInDays {
            expiryDaysText = "Expires in \(days) days"
        } else if let display = credentials?.expiryDisplay,
                  let days = Self.daysUntil(display) {
            expiryDaysText = "Expires in \(days) days"
        } else {
            // Matches Android screenshot fallback when days are known from expiry date.
            expiryDaysText = Self.defaultExpiryDaysText(from: credentials?.expiryDisplay)
        }

        if let display = credentials?.expiryDisplay, !display.isEmpty {
            expiryDateText = "Expiry: \(Self.formatExpiry(display))"
        } else {
            expiryDateText = "Expiry: —"
        }

        bindService()
        bindRecorder()
        localHostSessionRole = meetingService.localHostSessionRole
        bothHostAndCoHostPresent = meetingService.bothHostAndCoHostPresent
        self.settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cloudRecordings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        playbackController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.recorder.start()
        self.recorder.setSpeechActive(!meetingService.speakingParticipantIDs.isEmpty)
        recordingBanner = .stopped
        loadRecordings()
        if connectionState == .connected {
            presentMeetingRecordingNoticeIfNeeded()
        }
    }

    func dismissMeetingRecordingNotice() {
        showMeetingRecordingNotice = false
    }

    private func presentMeetingRecordingNoticeIfNeeded() {
        guard !hasShownMeetingRecordingNotice else { return }
        guard recorder.isRecording else { return }
        guard connectionState == .connected, !isWaitingForHost else { return }
        hasShownMeetingRecordingNotice = true
        showMeetingRecordingNotice = true
    }

    private func bindService() {
        isMuted = true
        isSpeakerOn = meetingService.isSpeakerOn
        isEarphoneMode = meetingService.isEarphoneMode
        participants = meetingService.participants
        knownParticipantIDs = Set(participants.map(\.id))
        connectionState = meetingService.connectionState
        networkQuality = meetingService.networkQuality

        meetingService.onParticipantsChange = { [weak self] list in
            self?.handleParticipantsChange(list)
        }
        meetingService.onMuteChange = { [weak self] muted in
            self?.isMuted = muted
        }
        meetingService.onAudioRouteChange = { [weak self] speaker, earphone in
            self?.isSpeakerOn = speaker
            self?.isEarphoneMode = earphone
        }
        meetingService.onNetworkQualityChange = { [weak self] quality in
            self?.networkQuality = quality
        }
        meetingService.onParticipantNetworkQualityChange = { [weak self] id, quality in
            guard let self else { return }
            var next = self.participantNetworkQuality
            next[id] = quality
            self.participantNetworkQuality = next
        }
        meetingService.onStateChange = { [weak self] state in
            guard let self else { return }
            self.connectionState = state
            switch state {
            case .ended:
                self.showMeetingRecordingNotice = false
                guard !self.isDisconnecting else { return }
                Task {
                    await self.disconnectAndGoHome {
                        self.recorder.stop()
                        self.recordingBanner = .stopped
                    }
                }
            case .connecting, .waitingForHost, .hostLeft, .reconnecting:
                self.showMeetingRecordingNotice = false
            case .connected:
                self.presentMeetingRecordingNoticeIfNeeded()
            default:
                break
            }
        }
        meetingService.onSpeakingParticipantsChange = { [weak self] ids in
            self?.recorder.setSpeechActive(!ids.isEmpty)
            self?.handleSpeakingParticipantsChange(ids)
        }
        meetingService.onActiveSpeakerChange = { [weak self] id in
            guard let self else { return }
            if let id {
                // Hint only — poll/`isTalking` remains source of truth and will
                // clear this quickly if the user is muted or silent.
                if !self.speakingParticipantIDs.contains(id) {
                    self.speakingParticipantIDs.insert(id)
                }
            } else {
                self.speakingClearTask?.cancel()
                self.speakingParticipantIDs = []
            }
        }
        meetingService.onHostStatusReceived = { [weak self] message in
            self?.presentStatusBanner(message)
        }
        meetingService.onParticipantListeningStateChange = { [weak self] participantID, isPaused in
            self?.applyParticipantListeningState(id: participantID, isPaused: isPaused)
        }
        meetingService.onParticipantAudioRouteChange = { [weak self] participantID, isHandsfree in
            self?.applyParticipantAudioRoute(id: participantID, isHandsfree: isHandsfree)
        }
        meetingService.onMeetingRemainingMinutesChange = { [weak self] minutes in
            self?.meetingRemainingMinutes = minutes
        }
        meetingService.onPaymentPendingDetected = { [weak self] in
            self?.isPaymentPending = true
        }
        meetingService.onMeetingTimeLimitEndsAt = { [weak self] endsAt in
            self?.meetingLimitEndsAt = endsAt
        }
        meetingService.onHostSessionLayoutChange = { [weak self] role, bothPresent in
            self?.localHostSessionRole = role
            self?.bothHostAndCoHostPresent = bothPresent
        }
    }

    private func bindRecorder() {
        recorder.onFilesChanged = { [weak self] in
            self?.loadRecordings()
            self?.syncRecordingBannerFromRecorder()
        }
    }

    private func loadRecordings() {
        recordings = recorder.loadFiles()
    }

    private func handleParticipantsChange(_ list: [MeetingParticipant]) {
        let previousByID = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
        let newIDs = Set(list.map(\.id))
        let joined = newIDs.subtracting(knownParticipantIDs)
        participants = list
        knownParticipantIDs = newIDs

        joiningParticipantIDs = joiningParticipantIDs.intersection(newIDs)
        pausedListeningIDs = pausedListeningIDs.intersection(newIDs)
        handsfreeParticipantIDs = handsfreeParticipantIDs.intersection(newIDs)
        hadAudioConnectedIDs = hadAudioConnectedIDs.intersection(newIDs)
        audioDisconnectedIDs = audioDisconnectedIDs.intersection(newIDs)
        participantNetworkQuality = participantNetworkQuality.filter { newIDs.contains($0.key) }

        for participant in list where isAttendee(participant) {
            let id = participant.id
            let previouslyConnected = previousByID[id]?.isAudioConnected == true
                || hadAudioConnectedIDs.contains(id)
            let previouslyDisconnected = previousByID[id]?.isAudioConnected == false
                || audioDisconnectedIDs.contains(id)

            if participant.isAudioConnected {
                hadAudioConnectedIDs.insert(id)
                // Android Resume reconnects VoIP without always sending iOS-style
                // resume chat — clear yellow/orange pause + join flash.
                if previouslyDisconnected || audioDisconnectedIDs.contains(id) {
                    audioDisconnectedIDs.remove(id)
                    pausedListeningIDs.remove(id)
                    joiningParticipantIDs.remove(id)
                    joiningClearTasks[id]?.cancel()
                    joiningClearTasks[id] = nil
                }
            } else if previouslyConnected {
                audioDisconnectedIDs.insert(id)
                // Android pause (audio disconnect) should not stay under join-flash yellow.
                joiningParticipantIDs.remove(id)
            }
        }

        for id in joined {
            // Fresh joiner — not an Android audio-reconnect of an existing seat.
            if audioDisconnectedIDs.contains(id) { continue }
            markJoining(id)
        }

        // Drop speaking highlight for muted / left users immediately.
        let mutedOrGone = speakingParticipantIDs.filter { id in
            guard let participant = list.first(where: { $0.id == id }) else { return true }
            return participant.isMuted
        }
        if !mutedOrGone.isEmpty {
            speakingParticipantIDs.subtract(mutedOrGone)
        }

        // Header: spinning refresh while remote list is empty; network after someone unmutes.
        if list.filter({ isAttendee($0) }).isEmpty {
            showHostNetworkInHeader = false
        } else if list.contains(where: { isAttendee($0) && !$0.isMuted }) {
            showHostNetworkInHeader = true
        }

        updateStickyUnmutedIDs(from: list)
        syncTransmitterActivityBanner()
    }

    /// Absorbs brief Zoom `isMuted` flips so Recording / top chrome don't blink.
    private func updateStickyUnmutedIDs(from list: [MeetingParticipant]) {
        let currentIDs = Set(list.map(\.id))
        stickyUnmutedIDs = stickyUnmutedIDs.intersection(currentIDs)
        for taskID in unmuteClearTasks.keys where !currentIDs.contains(taskID) {
            unmuteClearTasks[taskID]?.cancel()
            unmuteClearTasks[taskID] = nil
        }

        for participant in list where isAttendee(participant) {
            let id = participant.id
            if !participant.isMuted {
                unmuteClearTasks[id]?.cancel()
                unmuteClearTasks[id] = nil
                stickyUnmutedIDs.insert(id)
            } else if stickyUnmutedIDs.contains(id), unmuteClearTasks[id] == nil {
                unmuteClearTasks[id] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Self.unmuteHoldNanoseconds)
                    guard let self, !Task.isCancelled else { return }
                    self.stickyUnmutedIDs.remove(id)
                    self.unmuteClearTasks[id] = nil
                    self.syncTransmitterActivityBanner()
                }
            }
        }
    }

    /// Recording... while any participant mic is unmuted; Stopping 5s→hide when
    /// the last one mutes. UI only — does not stop `LocalRecordingRecorder`.
    private func syncTransmitterActivityBanner() {
        let liveIDs = stickyUnmutedIDs
        if !liveIDs.isEmpty {
            recordingMuteClearTask?.cancel()
            recordingMuteClearTask = nil
            recordingStopTask?.cancel()
            recordingStopTask = nil
            recordingBanner = .recording
            hadLiveTransmitters = true
        } else if hadLiveTransmitters {
            // Extra beat so a mute blip mid-speech doesn't restart Stopping.
            guard recordingMuteClearTask == nil else { return }
            recordingMuteClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.unmuteHoldNanoseconds)
                guard let self, !Task.isCancelled else { return }
                self.recordingMuteClearTask = nil
                guard self.stickyUnmutedIDs.isEmpty, self.hadLiveTransmitters else { return }
                self.hadLiveTransmitters = false
                self.beginTransmitterStopCountdown()
            }
        }
    }

    private func beginTransmitterStopCountdown() {
        recordingStopTask?.cancel()
        recordingStopTask = Task { [weak self] in
            for second in stride(from: 2, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                // Someone unmuted again mid-countdown.
                if !self.stickyUnmutedIDs.isEmpty {
                    self.recordingBanner = .recording
                    self.hadLiveTransmitters = true
                    self.recordingStopTask = nil
                    return
                }
                self.recordingBanner = .stopping(secondsLeft: second)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.recordingBanner = .stopped
            self.recordingStopTask = nil
        }
    }

    private func applyParticipantListeningState(id: String, isPaused: Bool) {
        let resolved = resolveParticipantID(id)
        // After host taps Unlisten/Listen, ignore chat echoes for a moment so
        // the menu label doesn't oscillate (pause then resume aliases).
        if let until = hostUnlistenOverrideUntil[resolved], until > Date() {
            return
        }
        if isPaused {
            pausedListeningIDs.insert(resolved)
            // Don't let join-flash / handsfree yellow cover the paused (purple) card.
            joiningParticipantIDs.remove(resolved)
        } else {
            pausedListeningIDs.remove(resolved)
            joiningParticipantIDs.remove(resolved)
            joiningClearTasks[resolved]?.cancel()
            joiningClearTasks[resolved] = nil
        }
    }

    private func applyParticipantAudioRoute(id: String, isHandsfree: Bool) {
        let resolved = resolveParticipantID(id)
        if isHandsfree {
            handsfreeParticipantIDs.insert(resolved)
        } else {
            handsfreeParticipantIDs.remove(resolved)
        }
    }

    /// Zoom chat `senderId` should match `MeetingParticipant.id`; normalize
    /// whitespace / numeric formatting so Android + iOS both resolve.
    private func resolveParticipantID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if participants.contains(where: { $0.id == trimmed }) {
            return trimmed
        }
        if let asInt = UInt(trimmed) {
            let normalized = String(asInt)
            if participants.contains(where: { $0.id == normalized }) {
                return normalized
            }
        }
        return trimmed
    }

    private func markJoining(_ id: String) {
        joiningParticipantIDs.insert(id)
        joiningClearTasks[id]?.cancel()
        joiningClearTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.joiningParticipantIDs.remove(id)
            self.joiningClearTasks[id] = nil
        }
    }

    private func syncRecordingBannerFromRecorder() {
        // Banner is driven by participant mic activity (`syncTransmitterActivityBanner`),
        // not by local file-recorder state — keep recorder running in the background.
    }

    /// Legacy entry — kept for call sites; same UI countdown as transmitter mute.
    func beginRecordingStopCountdown() {
        beginTransmitterStopCountdown()
    }

    /// Applies voice-activity updates from the SDK (kept for future use).
    /// Host card / top pills are driven by mic mute state, not this.
    private func handleSpeakingParticipantsChange(_ ids: Set<String>) {
        speakingClearTask?.cancel()
        let liveIDs = ids.filter { id in
            guard let participant = participants.first(where: { $0.id == id }) else { return false }
            return !participant.isMuted
        }
        if !liveIDs.isEmpty {
            speakingParticipantIDs = liveIDs
        } else {
            speakingClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self, !Task.isCancelled else { return }
                self.speakingParticipantIDs = []
            }
        }
    }

    func toggleMute() {
        Task { await meetingService.toggleMute() }
    }

    func toggleSpeaker() {
        Task { await meetingService.toggleSpeaker() }
    }

    /// Match participant behavior:
    /// - Earphone tap: wired/Bluetooth if present, otherwise receiver earpiece.
    /// - Speaker tap: loudspeaker.
    func toggleEarphone() {
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

    func refresh() {
        Task { await meetingService.refreshConnection() }
    }

    func listenAll() {
        // Optimistically mark everyone listening (green) — participants also
        // report RESUMED after they apply Listen All locally.
        pausedListeningIDs.removeAll()
        Task { await meetingService.listenAll() }
    }

    // MARK: - Participant long-press menu

    func openParticipantMenu(_ participant: MeetingParticipant) {
        participantMenuTarget = participant
    }

    func dismissParticipantMenu() {
        participantMenuTarget = nil
    }

    func removeParticipantFromMenu() {
        guard let participant = participantMenuTarget else { return }
        participantMenuTarget = nil
        pausedListeningIDs.remove(participant.id)
        Task { await meetingService.removeParticipant(id: participant.id) }
    }

    /// Mute → pause participant (orange).
    /// Unmute → resume participant (green).
    /// Dismisses the popup after either action (Android).
    func toggleUnlistenFromMenu() {
        guard let participant = participantMenuTarget else { return }
        let id = participant.id
        // Match menu label: Android self-pause is audio-disconnect, not only
        // `pausedListeningIDs` (iOS chat path).
        if isListeningPaused(participant) {
            pausedListeningIDs.remove(id)
            Task { await meetingService.listenParticipant(id: id) }
        } else {
            pausedListeningIDs.insert(id)
            joiningParticipantIDs.remove(id)
            Task { await meetingService.unlistenParticipant(id: id) }
        }
        hostUnlistenOverrideUntil[id] = Date().addingTimeInterval(2.5)
        participantMenuTarget = nil
    }

    func unlistenParticipantFromMenu() {
        toggleUnlistenFromMenu()
    }

    // MARK: - Logout all / End meeting confirmations

    func requestLogoutAll() {
        showLogoutAllConfirm = true
    }

    func cancelLogoutAll() {
        showLogoutAllConfirm = false
    }

    func confirmLogoutAll() {
        showLogoutAllConfirm = false
        Task { await meetingService.logoutAll() }
    }

    func requestEndMeeting() {
        if bothHostAndCoHostPresent {
            showLeaveMeetingConfirm = true
        } else {
            showEndMeetingConfirm = true
        }
    }

    func cancelLeaveMeeting() {
        showLeaveMeetingConfirm = false
    }

    func confirmLeaveMeeting() {
        showLeaveMeetingConfirm = false
        Task {
            await disconnectAndGoHome {
                self.recorder.stop()
                await self.meetingService.leaveMeeting()
            }
        }
    }

    func cancelEndMeeting() {
        showEndMeetingConfirm = false
    }

    func confirmEndMeeting() {
        showEndMeetingConfirm = false
        Task {
            await disconnectAndGoHome {
                self.recorder.stop()
                await self.meetingService.endMeeting()
            }
        }
    }

    func leave() {
        Task {
            await disconnectAndGoHome {
                self.recorder.stop()
                await self.meetingService.leaveMeeting()
                await self.meetingService.deinitialize()
            }
        }
    }

    private func disconnectAndGoHome(_ work: () async -> Void) async {
        isDisconnecting = true
        await work()
        try? await Task.sleep(nanoseconds: 900_000_000)
        router.showHome()
    }

    // MARK: - Right side floating menu

    func toggleFloatingMenu() {
        showFloatingMenu.toggle()
    }

    /// Refreshes on-device recordings when the in-meeting Recordings panel opens.
    func reloadLocalRecordings() {
        loadRecordings()
    }

    func openRecordings() {
        showFloatingMenu = false
        loadRecordings()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showRecordings = true
        }
    }

    func openCloudRecordings() {
        showFloatingMenu = false
        showCloudRecordings = true
        Task { await cloudRecordings.load() }
    }

    func openSettings() {
        showFloatingMenu = false
        showSettings = true
    }

    func openStatus() {
        showFloatingMenu = false
        statusMessageDraft = ""
        showStatusSheet = true
    }

    func cancelStatus() {
        showStatusSheet = false
    }

    func sendStatus() {
        let message = statusMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        showStatusSheet = false
        statusMessageDraft = ""
        // Show immediately on host (SDK chat ignores own messages).
        presentStatusBanner(message)
        Task { await meetingService.sendStatusToAll(message) }
    }

    func dismissStatusBanner() {
        guard statusBannerMessage != nil else { return }
        statusBannerMessage = nil
        Task { await meetingService.removeStatusFromAll() }
    }

    private func presentStatusBanner(_ message: String) {
        var trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty
            || lower == "removestatusmessage"
            || lower == "removestatus"
            || lower == "clearstatusmessage"
            || lower == "clearstatus"
            || lower.hasPrefix("removestatusmessage")
            || lower.contains("removestatusmessage") {
            statusBannerMessage = nil
            return
        }
        let prefixes = ["addstatusmessage:", "addstatusmessage", "statusmessage:", "status:"]
        for prefix in prefixes {
            if trimmed.lowercased().hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let display = trimmed.lowercased()
        if display.isEmpty
            || display == "removestatusmessage"
            || display.contains("removestatusmessage") {
            statusBannerMessage = nil
            return
        }
        statusBannerMessage = trimmed
    }

    // MARK: - Local recordings

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

    // MARK: - Expiry helpers

    private static func defaultExpiryDaysText(from raw: String?) -> String {
        if let raw, let days = daysUntil(raw) {
            return "Expires in \(days) days"
        }
        return "Expires in — days"
    }

    private static func daysUntil(_ raw: String) -> Int? {
        let formats = ["yyyy-MM-dd", "dd MMM yyyy", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
                return days
            }
        }
        return nil
    }

    private static func formatExpiry(_ raw: String) -> String {
        let formats = ["yyyy-MM-dd", "dd MMM yyyy", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "en_US_POSIX")
                out.dateFormat = "dd MMM yyyy"
                return out.string(from: date)
            }
        }
        return raw
    }
}
