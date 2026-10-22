//
//  ZoomAudioMeetingService.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import AVFoundation
import Foundation

#if canImport(MobileRTC)
import MobileRTC
#endif

/// Zoom-backed implementation of `AudioMeetingServiceProtocol`.
/// SwiftUI never imports MobileRTC — only this infrastructure type does.
/// Inherits `NSObject` because `MobileRTCMeetingServiceDelegate` requires `NSObjectProtocol` conformance.
@MainActor
final class ZoomAudioMeetingService: NSObject, AudioMeetingServiceProtocol {
    private(set) var connectionState: MeetingConnectionState = .idle
    private(set) var participants: [MeetingParticipant] = []
    private(set) var isMuted = true
    private(set) var isSpeakerOn = true
    private(set) var isEarphoneMode = false
    private(set) var isLocalAudioPaused = false
    private(set) var networkQuality: NetworkQuality = .unknown
    private(set) var hostNetworkQuality: NetworkQuality = .unknown
    var speakingParticipantIDs: Set<String> { lastPublishedSpeakingIDs }

    var onStateChange: ((MeetingConnectionState) -> Void)?
    var onParticipantsChange: (([MeetingParticipant]) -> Void)?
    var onMuteChange: ((Bool) -> Void)?
    var onAudioRouteChange: ((Bool, Bool) -> Void)?
    var onNetworkQualityChange: ((NetworkQuality) -> Void)?
    var onHostNetworkQualityChange: ((NetworkQuality) -> Void)?
    var onParticipantNetworkQualityChange: ((String, NetworkQuality) -> Void)?
    var onSpeakingParticipantsChange: ((Set<String>) -> Void)?
    var onActiveSpeakerChange: ((String?) -> Void)?
    var onHostStatusReceived: ((String) -> Void)?
    var onHostUnavailable: (() -> Void)?
    var onHostAvatarChange: ((URL?) -> Void)?
    var onListenAllReceived: (() -> Void)?
    var onLogoutAllReceived: (() -> Void)?
    var onParticipantListeningStateChange: ((String, Bool) -> Void)?
    var onParticipantAudioRouteChange: ((String, Bool) -> Void)?
    var onHostForcedListeningPause: ((Bool) -> Void)?
    var onMeetingRemainingMinutesChange: ((Int) -> Void)?
    var onPaymentPendingDetected: (() -> Void)?
    var onMeetingTimeLimitEndsAt: ((Date?) -> Void)?
    var onHostSessionLayoutChange: ((HostSessionRole?, Bool) -> Void)?
    private(set) var meetingRemainingMinutes: Int? = nil
    private(set) var localHostSessionRole: HostSessionRole?
    private(set) var bothHostAndCoHostPresent = false

    /// Reserved chat payloads the host sends to trigger participant-side actions
    /// without showing a visible "Host Status" popup.
    private enum MeetingCommand {
        static let listenAll = "__TELECOM_CMD:LISTEN_ALL__"
        static let logoutAll = "__TELECOM_CMD:LOGOUT_ALL__"
        static let paused = "__TELECOM_CMD:PAUSED__"
        static let resumed = "__TELECOM_CMD:RESUMED__"
        static let handsfree = "__TELECOM_CMD:HANDSFREE__"
        static let speaker = "__TELECOM_CMD:SPEAKER__"
        static let removeStatus = "__TELECOM_CMD:REMOVE_STATUS__"
    }

    private let sdkManager = ZoomSDKManager.shared
    private var activeCredentials: ZoomMeetingCredentials?
    private var endFallbackTask: Task<Void, Never>?
    private var speakingPollTask: Task<Void, Never>?
    private var lastPublishedSpeakingIDs: Set<String> = []
    private var hasAppliedJoinMute = false
    private var didReportHostUnavailable = false
    private var meetingLimitStartedAt: Date?
    private var meetingTimeLimitSeconds: TimeInterval = 0
    private var remainingTimeTask: Task<Void, Never>?
    private var runtimePaymentPending = false
    private static let freeMeetingUpgradeByAdminRawValue: UInt = 1

    func initializeSDK(with credentials: ZoomMeetingCredentials) async throws {
        updateState(.preparing)
        try await requestMicrophonePermission()
        updateState(.initializingSDK)
        try await sdkManager.initialize(sdkKey: credentials.sdkKey, jwt: credentials.jwtOrSDKToken)
        updateState(.sdkReady)
    }

    func joinMeeting(with credentials: ZoomMeetingCredentials) async throws {
        activeCredentials = credentials
        didReportHostUnavailable = false
        runtimePaymentPending = false
        meetingRemainingMinutes = nil
        stopRemainingTimeTracking()
        if credentials.isHost, credentials.isPaymentPending {
            meetingTimeLimitSeconds = TimeInterval(max(1, credentials.meetingTimeLimitMinutes) * 60)
            meetingRemainingMinutes = credentials.meetingTimeLimitMinutes
        } else {
            meetingTimeLimitSeconds = 0
        }
        updateState(.connecting)

        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let meetingService = MobileRTC.shared().getMeetingService() else {
            throw NetworkError.unknown("Meeting service unavailable.")
        }
        // `MobileRTCMeetingServiceDelegate` is one large protocol that carries
        // meeting/audio/user/etc. callbacks together (see MobileRTCMeetingDelegate.h).
        meetingService.delegate = self

        if credentials.isHost, credentials.zak?.isEmpty != false {
            throw NetworkError.decodingFailed("Zoom access token missing for host.")
        }

        await waitUntilPreviousMeetingReleased()

        var result = beginOrJoinMeeting(credentials, meetingService: meetingService)
        if result.rawValue == 152 {
            await suppressNativeMeetingUI()
            meetingService.leaveMeeting(with: .leave)
            await waitUntilPreviousMeetingReleased()
            result = beginOrJoinMeeting(credentials, meetingService: meetingService)
        }

        if result != .success {
            let message = "Unable to connect to meeting (\(result))."
            await suppressNativeMeetingUI()
            updateState(.failed(message))
            throw NetworkError.unknown(message)
        }

        await suppressNativeMeetingUI()
        await waitForJoinSettlement(timeoutSeconds: 20)
        await suppressNativeMeetingUI()
        #else
        // Development stub: simulate connecting without MobileRTC.
        try await Task.sleep(nanoseconds: 600_000_000)
        isMuted = true
        onMuteChange?(true)
        if credentials.isHost {
            updateState(.connected)
        } else {
            // Android parity: Zoom JBH / waiting-for-host = line switch-off.
            updateState(.waitingForHost)
            reportHostUnavailableIfNeeded()
        }
        refreshParticipantsStub()
        networkQuality = .unknown
        hostNetworkQuality = .unknown
        #endif
    }

    func leaveMeeting() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        stopSpeakingPoll()
        publishSpeakingParticipants([])
        MobileRTC.shared().getMeetingService()?.leaveMeeting(with: .leave)
        participants = []
        onParticipantsChange?(participants)
        applyHostSessionLayout(role: nil, bothPresent: false)
        // `.ended` is set by `onMeetingStateChange` once the SDK confirms the
        // meeting actually ended; the fallback guards against a missed event.
        scheduleEndFallback()
        #else
        participants = []
        onParticipantsChange?(participants)
        applyHostSessionLayout(role: nil, bothPresent: false)
        onSpeakingParticipantsChange?([])
        updateState(.ended)
        #endif
    }

    func endMeeting() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        stopSpeakingPoll()
        publishSpeakingParticipants([])
        MobileRTC.shared().getMeetingService()?.leaveMeeting(with: .end)
        participants = []
        onParticipantsChange?(participants)
        applyHostSessionLayout(role: nil, bothPresent: false)
        scheduleEndFallback()
        #else
        // Stub: same as leave for non-host simulation.
        participants = []
        onParticipantsChange?(participants)
        applyHostSessionLayout(role: nil, bothPresent: false)
        onSpeakingParticipantsChange?([])
        updateState(.ended)
        #endif
    }

    func toggleMute() async {
        await setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        // Ensure VoIP audio is connected before unmuting.
        if !muted {
            _ = meetingService.connectMyAudio(true)
        }
        _ = meetingService.muteMyAudio(muted)
        // Update UI immediately on tap; the SDK delegate confirms shortly after.
        isMuted = muted
        onMuteChange?(muted)
        #else
        isMuted = muted
        onMuteChange?(muted)
        #endif
    }

    func setLocalAudioPaused(_ paused: Bool) async {
        isLocalAudioPaused = paused
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        if !paused {
            _ = meetingService.connectMyAudio(true)
        }
        _ = meetingService.stopIncomingAudio(paused)
        #endif
    }

    /// Tell the host this participant paused/resumed listening (card purple/green).
    /// Sends Telecom command plus plain Android-compatible tokens.
    func reportListeningPaused(_ paused: Bool) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        if paused {
            await sendCommandToHost(MeetingCommand.paused)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await sendCommandToHost("pause")
            try? await Task.sleep(nanoseconds: 150_000_000)
            await sendCommandToHost("paused")
        } else {
            await sendCommandToHost(MeetingCommand.resumed)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await sendCommandToHost("resume")
            try? await Task.sleep(nanoseconds: 150_000_000)
            await sendCommandToHost("resumed")
            // After resume, re-assert current route so host card is yellow/green.
            try? await Task.sleep(nanoseconds: 150_000_000)
            await reportAudioRoute(isHandsfree: isEarphoneMode)
        }
        #endif
    }

    /// Tell the host handsfree/earphone vs speaker for participant card color.
    func reportAudioRoute(isHandsfree: Bool) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        if isHandsfree {
            await sendCommandToHost(MeetingCommand.handsfree)
            try? await Task.sleep(nanoseconds: 150_000_000)
            await sendCommandToHost("handsfree")
            try? await Task.sleep(nanoseconds: 120_000_000)
            await sendCommandToHost("earphone")
        } else {
            await sendCommandToHost(MeetingCommand.speaker)
            try? await Task.sleep(nanoseconds: 150_000_000)
            await sendCommandToHost("speaker")
            try? await Task.sleep(nanoseconds: 120_000_000)
            await sendCommandToHost("speakerphone")
        }
        #endif
    }

    func toggleSpeaker() async {
        isSpeakerOn.toggle()
        if isSpeakerOn {
            isEarphoneMode = false
        }
        applyAudioRoute()
        onAudioRouteChange?(isSpeakerOn, isEarphoneMode)
    }

    func setEarphoneMode(_ enabled: Bool) async {
        isEarphoneMode = enabled
        if enabled {
            isSpeakerOn = false
        } else {
            isSpeakerOn = true
        }
        applyAudioRoute()
        onAudioRouteChange?(isSpeakerOn, isEarphoneMode)
        await reportAudioRoute(isHandsfree: enabled)
    }

    func refreshConnection() async {
        guard let credentials = activeCredentials else { return }
        updateState(.reconnecting)
        do {
            try await joinMeeting(with: credentials)
        } catch {
            updateState(.failed(error.localizedDescription))
        }
    }

    func listenAll() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        // Broadcast to every participant. Staggered DMs avoid Zoom rate-limits
        // that previously only reached the first joiner.
        await broadcastCommandToEveryParticipant(MeetingCommand.listenAll)
        try? await Task.sleep(nanoseconds: 350_000_000)
        // Android alias — some builds only listen for the plain "listen" token.
        await broadcastCommandToEveryParticipant("listen")
        #else
        onListenAllReceived?()
        #endif
    }

    func logoutAll() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        // Signal participants first so they can show the waiting screen before
        // `removeUser` tears down their meeting session.
        await sendMeetingCommand(MeetingCommand.logoutAll)

        guard let meetingService = MobileRTC.shared().getMeetingService(),
              let userIDs = meetingService.getInMeetingUserList() else { return }
        let selfID = meetingService.myselfUserID()
        for number in userIDs where number.uintValue != selfID {
            _ = meetingService.removeUser(number.uintValue)
        }
        #else
        onLogoutAllReceived?()
        #endif
    }

    func removeParticipant(id: String) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let userID = UInt(id),
              let meetingService = MobileRTC.shared().getMeetingService() else {
            #if DEBUG
            print("removeParticipant: invalid id or meeting service (\(id))")
            #endif
            return
        }
        guard meetingService.isMeetingHost() || meetingService.isMeetingCoHost() else {
            #if DEBUG
            print("removeParticipant: not host/cohost")
            #endif
            return
        }
        let removed = meetingService.removeUser(userID)
        #if DEBUG
        print("removeParticipant user=\(userID) ok=\(removed)")
        #endif
        // SDK list can lag briefly after a successful kick.
        try? await Task.sleep(nanoseconds: 300_000_000)
        refreshParticipants()
        if participants.contains(where: { $0.id == id }) {
            _ = meetingService.removeUser(userID)
            try? await Task.sleep(nanoseconds: 300_000_000)
            refreshParticipants()
        }
        #else
        participants.removeAll { $0.id == id }
        onParticipantsChange?(participants)
        #endif
    }

    func unlistenParticipant(id: String) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let userID = UInt(id),
              let meetingService = MobileRTC.shared().getMeetingService() else { return }
        let userName = meetingService.userInfo(byID: userID)?.userName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Android often misses private DMs (iOS→iOS DMs work). Send DM + To_All
        // with Android-compatible tokens and user-targeted payloads.
        await forceParticipantListening(
            userID: userID,
            userName: userName,
            paused: true
        )
        _ = meetingService.muteUserAudio(true, withUID: userID)
        refreshParticipants()
        #endif
    }

    func listenParticipant(id: String) async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let userID = UInt(id),
              let meetingService = MobileRTC.shared().getMeetingService() else { return }
        let userName = meetingService.userInfo(byID: userID)?.userName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        await forceParticipantListening(
            userID: userID,
            userName: userName,
            paused: false
        )
        refreshParticipants()
        #endif
    }

    func sendStatusToAll(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        // iOS participants accept the plain status text.
        await sendMeetingCommand(trimmed)
        try? await Task.sleep(nanoseconds: 250_000_000)
        // Android Telecom listens for the `addstatusmessage:` protocol prefix
        // (same as Android hosts send). Without it, Android drops the message.
        await sendMeetingCommand("addstatusmessage:\(trimmed)")
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Legacy Android alias.
        await sendMeetingCommand("statusmessage:\(trimmed)")
        #else
        try? await Task.sleep(nanoseconds: 300_000_000)
        onHostStatusReceived?(trimmed)
        #endif
    }

    func removeStatusFromAll() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        // Android treats `addstatusmessage:` / `statusmessage:` as *display* payloads.
        // Sending those with "removestatusmessage" makes Android show that literal text.
        await sendMeetingCommand("removestatusmessage")
        try? await Task.sleep(nanoseconds: 200_000_000)
        await sendMeetingCommand(MeetingCommand.removeStatus)
        #else
        try? await Task.sleep(nanoseconds: 300_000_000)
        onHostStatusReceived?("")
        #endif
    }

    #if ZOOM_MEETING_SDK && canImport(MobileRTC)
    /// Sends a host-only command/status string to every in-meeting participant
    /// via Zoom chat. Must use `MobileRTCMeetingChatBuilder` — constructing
    /// `MobileRTCMeetingChat()` and setting properties is receive-only and
    /// never reaches Android (or other) clients.
    private func sendMeetingCommand(_ payload: String) async {
        await broadcastCommandToEveryParticipant(payload)
    }

    /// To_All first, then individual DMs with spacing so every joiner receives it.
    private func broadcastCommandToEveryParticipant(_ payload: String) async {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        guard !meetingService.isChatDisabled() else {
            #if DEBUG
            print("Zoom chat disabled — cannot send: \(payload)")
            #endif
            return
        }

        if activeCredentials?.isHost == true {
            _ = meetingService.changeAttendeeChatPriviledge(.everyone_Publicly_And_Privately)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        func sendToAll() -> MobileRTCSendChatError {
            guard let chat = MobileRTCMeetingChatBuilder()
                .setContent(payload)?
                .setMessageType(.to_All)?
                .build() else { return .failed }
            return meetingService.sendChatMsg(chat)
        }

        func sendToUser(_ userID: UInt) -> MobileRTCSendChatError {
            guard let chat = MobileRTCMeetingChatBuilder()
                .setContent(payload)?
                .setMessageType(.to_Individual)?
                .setReceiver(NSInteger(userID))?
                .build() else { return .failed }
            return meetingService.sendChatMsg(chat)
        }

        var result = sendToAll()
        if result != .successed {
            try? await Task.sleep(nanoseconds: 300_000_000)
            result = sendToAll()
        }
        #if DEBUG
        if result != .successed {
            print("Zoom To_All chat failed (\(result)) for: \(payload)")
        }
        #endif

        // Per-user DMs — required when To_All is dropped for later joiners.
        if let userIDs = meetingService.getInMeetingUserList() {
            let selfID = meetingService.myselfUserID()
            for number in userIDs where number.uintValue != selfID {
                var dmResult = sendToUser(number.uintValue)
                if dmResult != .successed {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    dmResult = sendToUser(number.uintValue)
                }
                #if DEBUG
                if dmResult != .successed {
                    print("Zoom DM chat failed (\(dmResult)) user=\(number.uintValue)")
                }
                #endif
                // Spacing prevents Zoom from silently dropping later DMs.
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }

    /// Participant → host private (+ To_All fallback) for pause/resume card sync.
    private func sendCommandToHost(_ payload: String) async {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        guard !meetingService.isChatDisabled() else { return }

        func sendToUser(_ userID: UInt) -> MobileRTCSendChatError {
            guard let chat = MobileRTCMeetingChatBuilder()
                .setContent(payload)?
                .setMessageType(.to_Individual)?
                .setReceiver(NSInteger(userID))?
                .build() else { return .failed }
            return meetingService.sendChatMsg(chat)
        }

        func sendToAll() -> MobileRTCSendChatError {
            guard let chat = MobileRTCMeetingChatBuilder()
                .setContent(payload)?
                .setMessageType(.to_All)?
                .build() else { return .failed }
            return meetingService.sendChatMsg(chat)
        }

        var sentToHost = false
        if let userIDs = meetingService.getInMeetingUserList() {
            let selfID = meetingService.myselfUserID()
            for number in userIDs where number.uintValue != selfID {
                guard let info = meetingService.userInfo(byID: number.uintValue),
                      info.isHost || info.isCohost else { continue }
                var result = sendToUser(number.uintValue)
                if result != .successed {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    result = sendToUser(number.uintValue)
                }
                if result == .successed {
                    sentToHost = true
                }
            }
        }

        // Always To_All as well — Android hosts may miss private DMs.
        _ = sendToAll()
        if !sentToHost {
            try? await Task.sleep(nanoseconds: 200_000_000)
            _ = sendToAll()
        }
    }

    /// Host → one participant (DM + Android To_All fallbacks).
    private func sendCommandToParticipant(userID: UInt, payload: String) async {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        guard !meetingService.isChatDisabled() else { return }

        if activeCredentials?.isHost == true {
            _ = meetingService.changeAttendeeChatPriviledge(.everyone_Publicly_And_Privately)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        func sendToUser(_ uid: UInt) -> MobileRTCSendChatError {
            guard let chat = MobileRTCMeetingChatBuilder()
                .setContent(payload)?
                .setMessageType(.to_Individual)?
                .setReceiver(NSInteger(uid))?
                .build() else { return .failed }
            return meetingService.sendChatMsg(chat)
        }

        var result = sendToUser(userID)
        if result != .successed {
            try? await Task.sleep(nanoseconds: 250_000_000)
            result = sendToUser(userID)
        }
        #if DEBUG
        if result != .successed {
            print("Zoom DM to \(userID) failed (\(result)) for: \(payload)")
        }
        #endif
    }

    /// Unlisten / Listen for one user — DMs for iOS, To_All aliases for Android.
    private func forceParticipantListening(userID: UInt, userName: String, paused: Bool) async {
        let idToken = String(userID)
        let nameToken = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloads: [String]
        if paused {
            payloads = [
                MeetingCommand.paused,
                "pause",
                "paused",
                "unlisten",
                "addpausemessage:pause",
                "pausemessage:pause",
                "__TELECOM_CMD:PAUSE_USER:\(idToken)__",
                "pause:\(idToken)",
                "unlisten:\(idToken)",
                nameToken.isEmpty ? nil : "pause:\(nameToken)",
                nameToken.isEmpty ? nil : "unlisten:\(nameToken)"
            ].compactMap { $0 }
        } else {
            // Android resume / Listen often keys off plain "listen" (same as Listen All).
            payloads = [
                MeetingCommand.resumed,
                "listen",
                "resume",
                "resumed",
                "listening",
                "addlistenmessage:listen",
                "__TELECOM_CMD:RESUME_USER:\(idToken)__",
                "listen:\(idToken)",
                "resume:\(idToken)",
                nameToken.isEmpty ? nil : "listen:\(nameToken)",
                nameToken.isEmpty ? nil : "resume:\(nameToken)"
            ].compactMap { $0 }
        }

        for (index, payload) in payloads.enumerated() {
            await sendCommandToParticipant(userID: userID, payload: payload)
            // To_All — Android attendees frequently miss private chat.
            await sendToAllChat(payload)
            if index < payloads.count - 1 {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func sendToAllChat(_ payload: String) async {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        guard !meetingService.isChatDisabled() else { return }
        guard let chat = MobileRTCMeetingChatBuilder()
            .setContent(payload)?
            .setMessageType(.to_All)?
            .build() else { return }
        var result = meetingService.sendChatMsg(chat)
        if result != .successed {
            try? await Task.sleep(nanoseconds: 200_000_000)
            result = meetingService.sendChatMsg(chat)
        }
        #if DEBUG
        if result != .successed {
            print("Zoom To_All failed (\(result)) for: \(payload)")
        }
        #endif
    }
    #endif

    func suppressNativeMeetingUI() async {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        hideZoomMeetingUI()
        #endif
    }

    func deinitialize() async {
        await leaveMeeting()
        sdkManager.deinitialize()
        activeCredentials = nil
        isLocalAudioPaused = false
        networkQuality = .unknown
        hostNetworkQuality = .unknown
        hasAppliedJoinMute = false
        stopRemainingTimeTracking()
        meetingRemainingMinutes = nil
        runtimePaymentPending = false
        updateState(.idle)
    }

    // MARK: - Private

    private func updateState(_ state: MeetingConnectionState) {
        connectionState = state
        onStateChange?(state)
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        if state == .connected {
            startSpeakingPoll()
        } else {
            stopSpeakingPoll()
            publishSpeakingParticipants([])
        }
        #endif
        switch state {
        case .ended, .failed, .idle, .hostLeft:
            hasAppliedJoinMute = false
            stopRemainingTimeTracking()
        default:
            break
        }
    }

    private func shouldTrackMeetingTimeLimit() -> Bool {
        guard activeCredentials?.isHost == true else { return false }
        if activeCredentials?.isPaymentPending == true || runtimePaymentPending { return true }
        return false
    }

    private func startRemainingTimeTrackingIfNeeded() {
        guard shouldTrackMeetingTimeLimit() else { return }
        if meetingTimeLimitSeconds <= 0 {
            let minutes = activeCredentials?.meetingTimeLimitMinutes ?? ZoomPaymentStatus.defaultMeetingLimitMinutes
            meetingTimeLimitSeconds = TimeInterval(max(1, minutes) * 60)
        }

        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        let sdkStart = MobileRTCInviteHelper.sharedInstance().ongoingMeetingStartTime
        meetingLimitStartedAt = sdkStart ?? Date()
        #else
        meetingLimitStartedAt = Date()
        #endif

        publishRemainingMinutes(currentRemainingMinutes())
        if let start = meetingLimitStartedAt {
            onMeetingTimeLimitEndsAt?(start.addingTimeInterval(meetingTimeLimitSeconds))
        }
        remainingTimeTask?.cancel()
        remainingTimeTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.connectionState == .connected {
                self.publishRemainingMinutes(self.currentRemainingMinutes())
                if self.meetingRemainingMinutes == 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopRemainingTimeTracking() {
        remainingTimeTask?.cancel()
        remainingTimeTask = nil
        meetingLimitStartedAt = nil
        onMeetingTimeLimitEndsAt?(nil)
    }

    private func currentRemainingMinutes() -> Int {
        guard meetingTimeLimitSeconds > 0 else {
            return activeCredentials?.meetingTimeLimitMinutes ?? ZoomPaymentStatus.defaultMeetingLimitMinutes
        }
        guard let start = meetingLimitStartedAt else {
            return Int(ceil(meetingTimeLimitSeconds / 60))
        }
        let elapsed = Date().timeIntervalSince(start)
        let remainingSeconds = max(0, meetingTimeLimitSeconds - elapsed)
        return max(0, Int(ceil(remainingSeconds / 60)))
    }

    private func publishRemainingMinutes(_ minutes: Int) {
        meetingRemainingMinutes = minutes
        onMeetingRemainingMinutesChange?(minutes)
    }

    private func applyHostSessionLayout(role: HostSessionRole?, bothPresent: Bool) {
        localHostSessionRole = role
        bothHostAndCoHostPresent = bothPresent
        onHostSessionLayoutChange?(role, bothPresent)
    }

    private func markPaymentPendingFromSDK() {
        guard activeCredentials?.isHost == true else { return }
        runtimePaymentPending = true
        if meetingTimeLimitSeconds <= 0 {
            meetingTimeLimitSeconds = TimeInterval(
                max(1, activeCredentials?.meetingTimeLimitMinutes ?? ZoomPaymentStatus.defaultMeetingLimitMinutes) * 60
            )
        }
        onPaymentPendingDetected?()
        if connectionState == .connected {
            startRemainingTimeTrackingIfNeeded()
        }
    }

    private func requestMicrophonePermission() async throws {
        let session = AVAudioSession.sharedInstance()
        let granted = await withCheckedContinuation { continuation in
            session.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else {
            throw NetworkError.unknown("Microphone permission is required for audio meetings.")
        }
        // `.voiceChat` + playAndRecord keeps the session eligible for background
        // audio when the user switches apps (requires UIBackgroundModes=audio).
        try configureAudioSessionRoute(session)
    }

    private func applyAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        do {
            try configureAudioSessionRoute(session)
            if isEarphoneMode {
                try session.overrideOutputAudioPort(.none)
            } else if isSpeakerOn {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            // Non-fatal route failure.
        }
    }

    /// Earphone mode must NOT keep `.defaultToSpeaker`, otherwise iPhone keeps
    /// playing through the loudspeaker. When no wired/Bluetooth route exists,
    /// `.none` then falls back to the receiver earpiece.
    private func configureAudioSessionRoute(_ session: AVAudioSession) throws {
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
        if !isEarphoneMode {
            options.insert(.defaultToSpeaker)
        }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setActive(true, options: [])
    }

    private func refreshParticipantsStub() {
        participants = []
        onParticipantsChange?(participants)
    }

    #if ZOOM_MEETING_SDK && canImport(MobileRTC)
    /// After End, Zoom can stay in the previous meeting for a moment.
    /// Starting again then returns error 152 (`inAnotherMeeting`) and shows
    /// Zoom's failure card. Wait until the SDK is idle, then start once.
    private func waitUntilPreviousMeetingReleased() async {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        let stillActive: [MobileRTCMeetingState] = [
            .connecting, .inMeeting, .disconnecting, .reconnecting, .waitingForHost
        ]
        if stillActive.contains(meetingService.getMeetingState()) {
            meetingService.leaveMeeting(with: .leave)
        }
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if meetingService.getMeetingState() == .idle {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func beginOrJoinMeeting(
        _ credentials: ZoomMeetingCredentials,
        meetingService: MobileRTCMeetingService
    ) -> MobileRTCMeetError {
        func attempt() -> MobileRTCMeetError {
            if credentials.isHost {
                let params = MobileRTCMeetingStartParam4WithoutLoginUser()
                params.meetingNumber = credentials.meetingNumber
                params.userName = credentials.displayName
                params.zak = credentials.zak ?? ""
                params.noVideo = true
                return meetingService.startMeeting(with: params)
            }
            let params = MobileRTCMeetingJoinParam()
            params.meetingNumber = credentials.meetingNumber
            params.userName = credentials.displayName
            params.noVideo = true
            if !credentials.password.isEmpty {
                params.password = credentials.password
            }
            return meetingService.joinMeeting(with: params)
        }

        return attempt()
    }

    /// Defensive timeout in case the SDK never reports `.ended`/`.idle` after
    /// a leave/end call, so the UI doesn't get stuck mid-call.
    private func scheduleEndFallback() {
        endFallbackTask?.cancel()
        endFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.connectionState != .ended && self.connectionState != .idle {
                self.updateState(.ended)
            }
        }
    }

    /// Rebuilds the participants list from the SDK's live in-meeting user list.
    /// Excludes the local user — the host's own card should never appear in its
    /// own "Participants" grid/count, only everyone *else* in the meeting.
    private func refreshParticipants() {
        guard let meetingService = MobileRTC.shared().getMeetingService(),
              let userIDs = meetingService.getInMeetingUserList() else {
            participants = []
            onParticipantsChange?(participants)
            applyHostSessionLayout(role: nil, bothPresent: false)
            return
        }
        let selfID = meetingService.myselfUserID()
        participants = userIDs.compactMap { number -> MeetingParticipant? in
            let uid = number.uintValue
            guard uid != selfID,
                  let info = meetingService.userInfo(byID: uid) else { return nil }
            // Include the other host-line session (HOST / COHOST card); still hide self.
            return MeetingParticipant(
                id: String(uid),
                name: info.userName ?? "Participant",
                isMuted: info.audioStatus?.isMuted ?? false,
                isHost: info.isHost,
                isCohost: info.isCohost,
                isAudioConnected: (info.audioStatus?.audioType ?? .none) != .none
            )
        }
        onParticipantsChange?(participants)
        refreshHostSessionLayout()
        refreshSpeakingParticipants()
        refreshHostAvatar()
    }

    /// Host/co-host chrome: local HOST vs COHOST badge and End vs Leave when both are in-meeting.
    private func refreshHostSessionLayout() {
        guard let meetingService = MobileRTC.shared().getMeetingService(),
              let userIDs = meetingService.getInMeetingUserList() else {
            applyHostSessionLayout(role: nil, bothPresent: false)
            return
        }

        let actingAsHost = activeCredentials?.isHost == true
            || meetingService.isMeetingHost()
            || meetingService.isMeetingCoHost()
        guard actingAsHost else {
            applyHostSessionLayout(role: nil, bothPresent: false)
            return
        }

        var anyHost = false
        var anyCohost = false
        for number in userIDs {
            guard let info = meetingService.userInfo(byID: number.uintValue) else { continue }
            if info.isHost { anyHost = true }
            if info.isCohost { anyCohost = true }
        }

        let role: HostSessionRole?
        if meetingService.isMeetingCoHost(), !meetingService.isMeetingHost() {
            role = .cohost
        } else if meetingService.isMeetingHost() {
            role = .host
        } else if meetingService.isMeetingCoHost() {
            role = .cohost
        } else if activeCredentials?.isHost == true {
            role = .host
        } else {
            role = nil
        }

        applyHostSessionLayout(role: role, bothPresent: anyHost && anyCohost)
    }

    /// Participant UI: load the remote host's Zoom profile image when available.
    private func refreshHostAvatar() {
        guard activeCredentials?.isHost != true else {
            onHostAvatarChange?(nil)
            return
        }
        guard let meetingService = MobileRTC.shared().getMeetingService(),
              let userIDs = meetingService.getInMeetingUserList() else {
            onHostAvatarChange?(nil)
            return
        }

        var hostFound = false
        for number in userIDs {
            let uid = number.uintValue
            guard let info = meetingService.userInfo(byID: uid), info.isHost else { continue }
            hostFound = true
            _ = meetingService.requestAvatar(forUser: uid)
            publishHostAvatar(from: info.avatarPath)
            break
        }
        if !hostFound {
            onHostAvatarChange?(nil)
        }
    }

    private func publishHostAvatar(from path: String?) {
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            onHostAvatarChange?(nil)
            return
        }
        onHostAvatarChange?(URL(fileURLWithPath: path))
    }

    /// Participant-only: Zoom waiting-for-host / JBH means host line is off (Android parity).
    private func reportHostUnavailableIfNeeded() {
        guard activeCredentials?.isHost != true, !didReportHostUnavailable else { return }
        didReportHostUnavailable = true
        onHostUnavailable?()
    }

    private func isJoinSettlementState(_ state: MeetingConnectionState) -> Bool {
        switch state {
        case .connecting, .idle, .preparing, .initializingSDK, .sdkReady:
            return false
        default:
            return true
        }
    }

    /// `joinMeeting(with:)` returns before Zoom fires `onMeetingStateChange`; wait
    /// so navigation can choose waiting vs connected vs logout.
    private func waitForJoinSettlement(timeoutSeconds: Double) async {
        guard !isJoinSettlementState(connectionState) else { return }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !isJoinSettlementState(connectionState), Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    #if ZOOM_MEETING_SDK && canImport(MobileRTC)
    private func hideZoomMeetingUI() {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        meetingService.hideMobileRTCMeeting { }
    }
    #endif

    #if ZOOM_MEETING_SDK && canImport(MobileRTC)
    private static func isHostUnavailableMeetError(_ error: MobileRTCMeetError) -> Bool {
        switch error {
        case .meetingNotStart,
             .meetingNotExist,
             .noMMR,
             .meetingOver,
             .meetingLocked,
             .meetingRestricted,
             .meetingRestrictedJBH,
             .vanityNotExist:
            return true
        default:
            return false
        }
    }
    #endif

    /// Scans every attendee's `audioStatus.isTalking` flag, including the local
    /// user, and publishes the ids currently speaking (real-time voice activity).
    /// Muted users never count as speaking — Zoom can leave `isTalking` sticky.
    private func refreshSpeakingParticipants() {
        guard let meetingService = MobileRTC.shared().getMeetingService(),
              let userIDs = meetingService.getInMeetingUserList() else {
            publishSpeakingParticipants([])
            return
        }
        var speaking = Set<String>()
        for number in userIDs {
            let uid = number.uintValue
            guard let info = meetingService.userInfo(byID: uid),
                  let audio = info.audioStatus,
                  !audio.isMuted,
                  audio.isTalking else { continue }
            speaking.insert(String(uid))
        }
        publishSpeakingParticipants(speaking)
    }

    private func publishSpeakingParticipants(_ speaking: Set<String>) {
        guard speaking != lastPublishedSpeakingIDs else { return }
        lastPublishedSpeakingIDs = speaking
        onSpeakingParticipantsChange?(speaking)
    }

    /// Poll `isTalking` while in-meeting — Zoom audio-only callbacks often miss
    /// the transition back to silence, which left host cards stuck red.
    private func startSpeakingPoll() {
        speakingPollTask?.cancel()
        speakingPollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.connectionState == .connected {
                self.refreshSpeakingParticipants()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopSpeakingPoll() {
        speakingPollTask?.cancel()
        speakingPollTask = nil
        lastPublishedSpeakingIDs = []
    }
    #endif
}

#if ZOOM_MEETING_SDK && canImport(MobileRTC)
// `MobileRTCMeetingServiceDelegate` (MobileRTCMeetingDelegate.h) is a single large
// protocol; its "Audio"/"User" sections below are just doc pragma markers, not
// separate Swift protocols.
extension ZoomAudioMeetingService: MobileRTCMeetingServiceDelegate {
    /// Zoom may poll this during join. Always false — CallKit was removed because
    /// it raced Zoom's audio stack and caused EXC_BAD_ACCESS on join.
    nonisolated func onCheckIfMeetingVoIPCallRunning() -> Bool {
        false
    }

    nonisolated func onMeetingStateChange(_ state: MobileRTCMeetingState) {
        Task { @MainActor in
            switch state {
            case .inMeeting:
                updateState(.connected)
                refreshParticipants()
                applyDefaultMutedOnJoin()
                enableMeetingChatForHost()
                await suppressNativeMeetingUI()
                startRemainingTimeTrackingIfNeeded()
            case .waitingForHost:
                updateState(.waitingForHost)
                await suppressNativeMeetingUI()
                reportHostUnavailableIfNeeded()
            case .connecting:
                updateState(.connecting)
                await suppressNativeMeetingUI()
            case .reconnecting:
                updateState(.reconnecting)
            case .failed:
                endFallbackTask?.cancel()
                updateState(.failed("Meeting connection failed"))
            case .ended, .idle:
                endFallbackTask?.cancel()
                participants = []
                onParticipantsChange?(participants)
                updateState(.ended)
            default:
                break
            }
        }
    }

    nonisolated func onMeetingError(_ error: MobileRTCMeetError, message: String?) {
        Task { @MainActor in
            guard activeCredentials?.isHost != true,
                  Self.isHostUnavailableMeetError(error) else { return }
            reportHostUnavailableIfNeeded()
        }
    }

    nonisolated func onJBHWaiting(with cmd: JBHCmd) {
        Task { @MainActor in
            await suppressNativeMeetingUI()
            if cmd == .show {
                updateState(.waitingForHost)
                reportHostUnavailableIfNeeded()
            }
        }
    }

    nonisolated func onMeetingReady() {
        Task { @MainActor in
            await suppressNativeMeetingUI()
        }
    }

    nonisolated func onJoinMeetingConfirmed() {
        Task { @MainActor in
            await suppressNativeMeetingUI()
        }
    }

    nonisolated func onFreeMeetingNeed(
        to type: FreeMeetingNeedUpgradeType,
        giftUpgradeURL: String?
    ) {
        Task { @MainActor in
            guard type.rawValue == ZoomAudioMeetingService.freeMeetingUpgradeByAdminRawValue else { return }
            markPaymentPendingFromSDK()
        }
    }

    nonisolated func onSinkMeetingUserJoin(_ userID: UInt) {
        Task { @MainActor in
            refreshParticipants()
            refreshHostAvatar()
        }
    }

    nonisolated func on(
        inMeetingUserAvatarPathUpdatedoninMeetingUserAvatarPathUpdated userID: Int
    ) {
        Task { @MainActor in
            guard activeCredentials?.isHost != true,
                  let meetingService = MobileRTC.shared().getMeetingService(),
                  let info = meetingService.userInfo(byID: UInt(userID)),
                  info.isHost else { return }
            publishHostAvatar(from: info.avatarPath)
        }
    }

    nonisolated func onSinkMeetingUserLeft(_ userID: UInt) {
        Task { @MainActor in refreshParticipants() }
    }

    /// Android Pause often disconnects VoIP (`AudioType_None`); reconnect = Resume.
    nonisolated func onSinkMeetingAudioTypeChange(_ userID: UInt) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func onSinkMeetingMyAudioTypeChange() {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func onSinkMeetingAudioStatusChange(_ userID: UInt) {
        Task { @MainActor in
            handleAudioStatusChange(userID: userID, listenAllSignal: false)
        }
    }

    /// Fires when the host mutes all / mutes a participant — used as a reliable
    /// Listen All fallback when the chat command is delayed or dropped.
    nonisolated func onSinkMeetingAudioStatusChange(_ userID: UInt, audioStatus: MobileRTC_AudioStatus) {
        Task { @MainActor in
            let listenAllSignal = Self.isHostListenAllSignal(audioStatus)
            handleAudioStatusChange(userID: userID, listenAllSignal: listenAllSignal)
        }
    }

    @MainActor
    private func handleAudioStatusChange(userID: UInt, listenAllSignal: Bool) {
        guard let meetingService = MobileRTC.shared().getMeetingService() else { return }
        if meetingService.myselfUserID() == userID {
            let muted = meetingService.isMyAudioMuted()
            isMuted = muted
            onMuteChange?(muted)
            if listenAllSignal {
                onListenAllReceived?()
            }
        }
        refreshParticipants()
        refreshSpeakingParticipants()
    }

    private static func isHostListenAllSignal(_ status: MobileRTC_AudioStatus) -> Bool {
        // Unmuted by host (4) or host unmuted all (6) — used when chat is delayed.
        switch status.rawValue {
        case 4, 6:
            return true
        default:
            return false
        }
    }

    /// Host enables public chat so Listen All / Status commands reach participants.
    private func enableMeetingChatForHost() {
        guard activeCredentials?.isHost == true,
              let meetingService = MobileRTC.shared().getMeetingService(),
              !meetingService.isChatDisabled() else { return }
        _ = meetingService.changeAttendeeChatPriviledge(.everyone_Publicly_And_Privately)
    }

    nonisolated func onUserNetworkStatusChanged(_ type: MobileRTCComponentType, level: MobileRTCNetworkQuality, userID: UInt, uplink: Bool) {
        Task { @MainActor in
            guard type == .AUDIO,
                  let meetingService = MobileRTC.shared().getMeetingService() else { return }
            // Prefer uplink for remotes (send quality); downlink still used when that's
            // what Zoom delivers for this callback tick.
            _ = uplink
            let quality = Self.bucket(level)
            let selfID = meetingService.myselfUserID()
            let localIsHost = activeCredentials?.isHost == true
                || meetingService.isMeetingHost()
                || meetingService.isMeetingCoHost()

            if selfID == userID {
                networkQuality = quality
                onNetworkQualityChange?(quality)
                // Host screen + participants' "host network" both need the host's live quality.
                if localIsHost {
                    hostNetworkQuality = quality
                    onHostNetworkQualityChange?(quality)
                }
            } else {
                // Live Zoom audio network quality for this remote participant.
                onParticipantNetworkQualityChange?(String(userID), quality)
            }
            if let info = meetingService.userInfo(byID: userID), info.isHost, userID != selfID {
                hostNetworkQuality = quality
                onHostNetworkQualityChange?(quality)
            }
        }
    }

    nonisolated func onNoHostMeetingWillTerminate(_ minutes: UInt) {
        Task { @MainActor in
            updateState(.hostLeft)
        }
    }

    nonisolated func onActiveSpeakerVideoUserChanged(_ userID: UInt) {
        Task { @MainActor in
            // Always re-scan isTalking — active-speaker events alone can stick
            // on the last talker after they mute/pause.
            refreshSpeakingParticipants()
            if userID == 0 {
                onActiveSpeakerChange?(nil)
            } else if let meetingService = MobileRTC.shared().getMeetingService(),
                      let info = meetingService.userInfo(byID: userID),
                      info.audioStatus?.isMuted != true,
                      info.audioStatus?.isTalking == true {
                onActiveSpeakerChange?(String(userID))
            } else {
                onActiveSpeakerChange?(nil)
            }
        }
    }

    nonisolated func onSinkUserNameChanged(_ userNameChangedArr: [NSNumber]?) {
        Task { @MainActor in
            refreshParticipants()
            guard activeCredentials?.isHost == true
                || MobileRTC.shared().getMeetingService()?.isMeetingHost() == true
                || MobileRTC.shared().getMeetingService()?.isMeetingCoHost() == true,
                  let meetingService = MobileRTC.shared().getMeetingService(),
                  let changed = userNameChangedArr else { return }
            for number in changed {
                let uid = number.uintValue
                guard let name = meetingService.userInfo(byID: uid)?.userName?.lowercased() else { continue }
                if name.contains("pause") || name.hasSuffix("|p") || name.contains("[p]") {
                    onParticipantListeningStateChange?(String(uid), true)
                } else if name.contains("resume") || name.hasSuffix("|r") {
                    onParticipantListeningStateChange?(String(uid), false)
                }
            }
        }
    }

    nonisolated func onMeetingHostChange(_ hostId: UInt) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func onMeetingCoHostChange(_ userID: UInt, isCoHost: Bool) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    /// Delivers chat messages, including host-broadcast "Status" messages sent
    /// via `sendStatusToAll`. Ignores messages this instance itself sent.
    nonisolated func onChatMessageNotification(_ chatInfo: MobileRTCMeetingChat?) {
        Task { @MainActor in
            guard let chatInfo, let content = chatInfo.content, !content.isEmpty,
                  let meetingService = MobileRTC.shared().getMeetingService() else { return }
            let selfID = String(meetingService.myselfUserID())
            guard chatInfo.senderId != selfID else { return }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            print("Zoom chat ← \(chatInfo.senderId ?? "?")/\(chatInfo.senderName ?? "?"): \(trimmed)")
            #endif

            let actingAsHost = activeCredentials?.isHost == true
                || meetingService.isMeetingHost()
                || meetingService.isMeetingCoHost()

            if actingAsHost, let pauseSender = Self.participantIDForPauseResume(
                content: trimmed,
                chatInfo: chatInfo,
                participants: participants,
                wantPaused: true
            ) {
                onParticipantListeningStateChange?(pauseSender, true)
            } else if actingAsHost, let resumeSender = Self.participantIDForPauseResume(
                content: trimmed,
                chatInfo: chatInfo,
                participants: participants,
                wantPaused: false
            ) {
                onParticipantListeningStateChange?(resumeSender, false)
            } else if actingAsHost, let androidRoute = Self.parseAndroidParticipantAudioRoute(trimmed) {
                // Android broadcasts `audio:<userId>:<Speaker|Earphone|…>`; the
                // user id is in the payload, not always the chat sender metadata.
                onParticipantAudioRouteChange?(androidRoute.participantID, androidRoute.isHandsfree)
            } else if actingAsHost, Self.isHandsfreeCommand(trimmed),
                      let routeSender = resolvedSenderID(from: chatInfo) {
                onParticipantAudioRouteChange?(routeSender, true)
            } else if actingAsHost, Self.isSpeakerRouteCommand(trimmed),
                      let routeSender = resolvedSenderID(from: chatInfo) {
                onParticipantAudioRouteChange?(routeSender, false)
            } else if !actingAsHost, Self.isPausedCommand(trimmed) {
                // Host Unlisten. Apply when:
                // - private DM (iOS path), or
                // - To_All targeted at me, or
                // - untargeted To_All pause/unlisten (Android path; other iOS
                //   clients ignore unless targeted / private).
                let forMe = Self.isForceListeningCommandForMe(
                    content: trimmed,
                    chatInfo: chatInfo,
                    selfID: selfID,
                    meetingService: meetingService
                )
                if forMe {
                    onHostForcedListeningPause?(true)
                }
            } else if !actingAsHost, Self.isResumedCommand(trimmed) {
                let forMe = Self.isForceListeningCommandForMe(
                    content: trimmed,
                    chatInfo: chatInfo,
                    selfID: selfID,
                    meetingService: meetingService
                )
                if forMe {
                    onHostForcedListeningPause?(false)
                }
            } else if Self.isListenAllCommand(trimmed) {
                if actingAsHost, let sender = resolvedSenderID(from: chatInfo) {
                    // Android participants often send plain "listen" when they
                    // resume — on the host that means card → green, not Listen All.
                    onParticipantListeningStateChange?(sender, false)
                } else {
                    onListenAllReceived?()
                }
            } else if Self.isLogoutAllCommand(trimmed) {
                onLogoutAllReceived?()
            } else if Self.isRemoveStatusCommand(trimmed) {
                // Host cleared status — participants must hide the banner, not
                // show the literal "removestatusmessage" token.
                onHostStatusReceived?("")
            } else if Self.isDisplayableHostStatus(trimmed) {
                // Only an explicit host status (`addstatusmessage:hi`) is shown.
                // Route noise such as `audio:16782336:Speaker` is not a command
                // and must not become a banner.
                onHostStatusReceived?(Self.displayableStatusMessage(trimmed))
            }
        }
    }

    /// Strips Android / legacy status-protocol prefixes so the banner shows plain text.
    private static func displayableStatusMessage(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "addstatusmessage:",
            "addstatusmessage",
            "addpausemessage:",
            "pausemessage:",
            "statusmessage:",
            "status:"
        ]
        for prefix in prefixes {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    private static func isRemoveStatusCommand(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        func matches(_ lower: String, upper: String) -> Bool {
            if lower == "removestatusmessage"
                || lower == "removestatus"
                || lower == "clearstatusmessage"
                || lower == "clearstatus"
                || lower == "deletestatusmessage"
                || lower == "deletestatus" {
                return true
            }
            if lower.hasPrefix("removestatusmessage")
                || lower.hasPrefix("removestatus:")
                || lower.hasPrefix("clearstatusmessage")
                || lower.hasPrefix("clearstatus:") {
                return true
            }
            return upper.contains("TELECOM_CMD:REMOVE_STATUS")
                || upper.contains("TELECOM_CMD:CLEAR_STATUS")
        }

        let lower = trimmed.lowercased()
        let upper = trimmed.uppercased()
        if matches(lower, upper: upper) { return true }

        let display = displayableStatusMessage(trimmed)
        return matches(display.lowercased(), upper: display.uppercased())
    }

    private func resolvedSenderID(from chatInfo: MobileRTCMeetingChat) -> String? {
        if let id = chatInfo.senderId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            if participants.contains(where: { $0.id == id }) { return id }
            if let asInt = UInt(id) {
                let normalized = String(asInt)
                if participants.contains(where: { $0.id == normalized }) { return normalized }
            }
            return id
        }
        guard let rawName = chatInfo.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else { return nil }
        let lowered = rawName.lowercased()
        return participants.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
        }?.id
    }

    /// Resolves which participant paused/resumed from chat content + sender metadata.
    private static func participantIDForPauseResume(
        content: String,
        chatInfo: MobileRTCMeetingChat,
        participants: [MeetingParticipant],
        wantPaused: Bool
    ) -> String? {
        let matches: Bool = {
            if wantPaused { return isPausedCommand(content) }
            return isResumedCommand(content) && !isListenAllCommand(content)
        }()
        guard matches else { return nil }

        if let id = chatInfo.senderId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            if participants.contains(where: { $0.id == id }) { return id }
            if let asInt = UInt(id) {
                let normalized = String(asInt)
                if participants.contains(where: { $0.id == normalized }) { return normalized }
            }
            return id
        }

        if let rawName = chatInfo.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            let lowered = rawName.lowercased()
            if let match = participants.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
            }) {
                return match.id
            }
        }

        // Content like "kussu1111:pause" / "pause:kussu1111"
        let token = displayableStatusMessage(content)
        let parts = token.split(whereSeparator: { ":|/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts {
            let lowered = part.lowercased()
            if lowered == "pause" || lowered == "paused" || lowered == "resume" || lowered == "resumed"
                || lowered == "listen" { continue }
            if let match = participants.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
            }) {
                return match.id
            }
        }
        return nil
    }

    private static func isListenAllCommand(_ content: String) -> Bool {
        if content == MeetingCommand.listenAll { return true }
        if content.caseInsensitiveCompare("listen") == .orderedSame { return true }
        return content.uppercased().contains("LISTEN_ALL")
    }

    private static func isLogoutAllCommand(_ content: String) -> Bool {
        if content == MeetingCommand.logoutAll { return true }
        if content.caseInsensitiveCompare("logout") == .orderedSame { return true }
        return content.uppercased().contains("LOGOUT_ALL")
    }

    private static func isPausedCommand(_ content: String) -> Bool {
        if content == MeetingCommand.paused { return true }
        let upper = content.uppercased()
        if upper.contains("TELECOM_CMD:PAUSED") { return true }
        if upper.contains("TELECOM_CMD:PAUSE_USER") { return true }
        let lower = content.lowercased()
        if lower.hasPrefix("addpausemessage") { return true }
        let token = displayableStatusMessage(content).lowercased()
        if token == "pause"
            || token == "paused"
            || token == "unlisten"
            || token == "userpause"
            || token == "user_pause"
            || token == "stopincomingaudio" {
            return true
        }
        // Android / targeted: "user pause", "pause:123", "unlisten:name", etc.
        if token.hasPrefix("pause:") || token.hasPrefix("unlisten:") { return true }
        return (token.contains("pause") || token.contains("unlisten")) && !token.contains("resume")
    }

    private static func isResumedCommand(_ content: String) -> Bool {
        if content == MeetingCommand.resumed { return true }
        let upper = content.uppercased()
        if upper.contains("TELECOM_CMD:RESUMED") { return true }
        if upper.contains("TELECOM_CMD:RESUME_USER") { return true }
        let lower = content.lowercased()
        if lower.hasPrefix("addlistenmessage") { return true }
        let token = displayableStatusMessage(content).lowercased()
        if token == "resume"
            || token == "resumed"
            || token == "listening"
            || token == "userresume"
            || token == "user_resume"
            || token == "startincomingaudio"
            || token == "unmute" {
            return true
        }
        // Targeted listen/resume — not plain "listen" (that is Listen All).
        if token.hasPrefix("resume:") || token.hasPrefix("listen:") { return true }
        if token.contains("resume") && !token.contains("pause") { return true }
        // Android often resumes with "listen" aliases beyond plain Listen All.
        if token == "userlisten" || token == "user_listen" || token.hasPrefix("listening:") {
            return true
        }
        return false
    }

    /// Whether a host force-pause/resume chat is meant for this device.
    private static func isForceListeningCommandForMe(
        content: String,
        chatInfo: MobileRTCMeetingChat,
        selfID: String,
        meetingService: MobileRTCMeetingService
    ) -> Bool {
        // Private DM → always for the receiver.
        if chatInfo.isPrivate { return true }
        if !chatInfo.isChatToAll, chatInfo.receiverId == selfID { return true }

        let lower = content.lowercased()
        let myID = selfID.lowercased()
        if lower.contains(":\(myID)") || lower.contains("pause_user:\(myID)")
            || lower.contains("resume_user:\(myID)")
            || lower.contains("_\(myID)_") {
            return true
        }

        if let rawName = meetingService.userInfo(byID: meetingService.myselfUserID())?.userName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            let name = rawName.lowercased()
            if lower.contains(":\(name)") || lower.hasSuffix(":\(name)") {
                return true
            }
        }

        // Untargeted To_All "pause"/"unlisten"/"resume" are for Android clients
        // that miss private DMs. iOS must ignore those so unlistensing one
        // Android user does not pause every iOS participant in the meeting.
        return false
    }

    /// Android in-meeting chat: `audio:<zoomUserId>:<route>` (see Android `audio` handler).
    private static func parseAndroidParticipantAudioRoute(
        _ content: String
    ) -> (participantID: String, isHandsfree: Bool)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("audio:") else { return nil }

        let body = String(trimmed.dropFirst("audio:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.split(separator: ":", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 else { return nil }
        let idPart = parts[0]
        guard idPart.allSatisfy(\.isNumber), let userID = UInt(idPart) else { return nil }

        let status = parts[1].lowercased()
        let speakerTokens = ["speaker", "speakerphone", "loudspeaker"]
        let earphoneTokens = ["earphone", "earpiece", "handsfree", "handfree", "receiver", "headphones", "headset"]
        if speakerTokens.contains(status) {
            return (String(userID), false)
        }
        if earphoneTokens.contains(status) {
            return (String(userID), true)
        }
        return nil
    }

    private static func isHandsfreeCommand(_ content: String) -> Bool {
        if content == MeetingCommand.handsfree { return true }
        if content.uppercased().contains("TELECOM_CMD:HANDSFREE") { return true }
        let token = displayableStatusMessage(content).lowercased()
        return token == "handsfree"
            || token == "handfree"
            || token == "earphone"
            || token == "earpiece"
            || token == "receiver"
    }

    private static func isSpeakerRouteCommand(_ content: String) -> Bool {
        if content == MeetingCommand.speaker { return true }
        if content.uppercased().contains("TELECOM_CMD:SPEAKER") { return true }
        let token = displayableStatusMessage(content).lowercased()
        return token == "speaker"
            || token == "speakerphone"
            || token == "loudspeaker"
    }

    /// Host status the banner is allowed to show. Everything else — including
    /// MeetingCommand payloads and stray chat — stays off screen.
    private static func isDisplayableHostStatus(_ content: String) -> Bool {
        let lower = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        let prefixes = [
            "addstatusmessage:",
            "statusmessage:",
            "status:"
        ]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// Host and participants join muted. Connect VoIP audio and enforce mute
    /// so the big mic button starts black/red until the user taps to unmute.
    private func applyDefaultMutedOnJoin() {
        guard !hasAppliedJoinMute,
              let meetingService = MobileRTC.shared().getMeetingService() else { return }
        hasAppliedJoinMute = true
        _ = meetingService.connectMyAudio(true)
        if !meetingService.isMyAudioMuted() {
            _ = meetingService.muteMyAudio(true)
        }
        isMuted = true
        onMuteChange?(true)
    }

    /// Buckets the SDK's 6-level `MobileRTCNetworkQuality` into a 3-color indicator.
    private static func bucket(_ level: MobileRTCNetworkQuality) -> NetworkQuality {
        switch level {
        case .veryBad, .bad:
            return .poor
        case .notGood, .normal:
            return .medium
        case .good, .excellent:
            return .good
        default:
            return .unknown
        }
    }
}
#endif
