//
//  MeetingConnectionState.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

enum MeetingConnectionState: Equatable, Sendable {
    case idle
    case preparing
    case initializingSDK
    case sdkReady
    case connecting
    case waitingForHost
    case connected
    case reconnecting
    /// Host left the meeting; the SDK will terminate it automatically unless a new host claims it.
    case hostLeft
    case failed(String)
    case ended
}

/// Local role when this device joined as meeting owner (host line or co-host duplicate session).
enum HostSessionRole: Equatable, Sendable {
    case host
    case cohost
}

struct MeetingParticipant: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isMuted: Bool
    let isHost: Bool
    let isCohost: Bool
    /// `false` when Zoom audio type is disconnected (`AudioType_None`).
    /// Android Pause often leaves meeting audio — host cards turn orange.
    let isAudioConnected: Bool
}

/// Bucketed connection quality shown by the on-screen network signal indicator.
/// Maps from the SDK's 6-level `MobileRTCNetworkQuality` (see `MobileRTCConstants.h`).
enum NetworkQuality: Equatable, Sendable {
    case unknown
    case poor
    case medium
    case good
}

@MainActor
protocol AudioMeetingServiceProtocol: AnyObject {
    var connectionState: MeetingConnectionState { get }
    var participants: [MeetingParticipant] { get }
    var isMuted: Bool { get }
    var isSpeakerOn: Bool { get }
    var isEarphoneMode: Bool { get }
    var isLocalAudioPaused: Bool { get }
    var networkQuality: NetworkQuality { get }
    var speakingParticipantIDs: Set<String> { get }
    /// Remote host's audio network quality (participant-side Host Network Indicator).
    var hostNetworkQuality: NetworkQuality { get }
    /// When this device is host or co-host: which label to show (HOST vs COHOST).
    var localHostSessionRole: HostSessionRole? { get }
    /// True when the meeting has at least one host and one co-host (dual host-line sessions).
    var bothHostAndCoHostPresent: Bool { get }

    var onStateChange: ((MeetingConnectionState) -> Void)? { get set }
    var onParticipantsChange: (([MeetingParticipant]) -> Void)? { get set }
    var onMuteChange: ((Bool) -> Void)? { get set }
    var onAudioRouteChange: ((Bool, Bool) -> Void)? { get set }
    var onNetworkQualityChange: ((NetworkQuality) -> Void)? { get set }
    var onHostNetworkQualityChange: ((NetworkQuality) -> Void)? { get set }
    /// Host-only: remote participant audio network quality (`participantID` → quality).
    var onParticipantNetworkQualityChange: ((String, NetworkQuality) -> Void)? { get set }
    /// Fires with the set of participant ids currently detected as speaking
    /// (voice activity via the SDK's `isTalking` flag). Empty when no one talks.
    var onSpeakingParticipantsChange: ((Set<String>) -> Void)? { get set }
    /// Fires with the currently-speaking participant's id (`MeetingParticipant.id`),
    /// or `nil` when no one is actively speaking. Backed by the SDK's active-speaker
    /// (voice activity) signal — only one active speaker is reported at a time.
    var onActiveSpeakerChange: ((String?) -> Void)? { get set }
    /// Fires on the participant side when the host broadcasts a status message.
    var onHostStatusReceived: ((String) -> Void)? { get set }
    /// Participant-side: host has not started the meeting / line is unavailable.
    var onHostUnavailable: (() -> Void)? { get set }
    /// Participant-side: local file URL for the remote host's Zoom avatar, if available.
    var onHostAvatarChange: ((URL?) -> Void)? { get set }
    /// Fires on the participant side when the host activates Listen All mode.
    var onListenAllReceived: (() -> Void)? { get set }
    /// Fires on the participant side when the host logs out all participants.
    var onLogoutAllReceived: (() -> Void)? { get set }
    /// Host-only: participant paused (`true`) or resumed listening (`false`).
    /// `participantID` matches `MeetingParticipant.id`.
    var onParticipantListeningStateChange: ((String, Bool) -> Void)? { get set }
    /// Host-only: participant audio route — `true` = handsfree/earphone, `false` = speaker.
    var onParticipantAudioRouteChange: ((String, Bool) -> Void)? { get set }
    /// Participant-side: host forced pause (`true` = Unlisten) or resume (`false` = Listen).
    var onHostForcedListeningPause: ((Bool) -> Void)? { get set }
    /// Host-only: minutes left before the payment-pending meeting cap (nil when not tracked).
    var meetingRemainingMinutes: Int? { get }
    var onMeetingRemainingMinutesChange: ((Int) -> Void)? { get set }
    /// Host-only: Zoom SDK reported admin payment / upgrade required.
    var onPaymentPendingDetected: (() -> Void)? { get set }
    /// Host-only: when the payment-pending meeting cap ends (for smooth UI countdown).
    var onMeetingTimeLimitEndsAt: ((Date?) -> Void)? { get set }
    /// Host/co-host UI: local role badge and End vs Leave button.
    var onHostSessionLayoutChange: ((HostSessionRole?, Bool) -> Void)? { get set }

    func initializeSDK(with credentials: ZoomMeetingCredentials) async throws
    func joinMeeting(with credentials: ZoomMeetingCredentials) async throws
    func leaveMeeting() async
    func endMeeting() async
    func toggleMute() async
    func setMuted(_ muted: Bool) async
    func toggleSpeaker() async
    func setEarphoneMode(_ enabled: Bool) async
    /// Stops/resumes incoming meeting audio for this device only — does not mute the
    /// mic, leave the meeting, or notify the host (`stopIncomingAudio:` on the SDK).
    func setLocalAudioPaused(_ paused: Bool) async
    /// Participant → host: report pause/resume so host cards can turn purple/green.
    func reportListeningPaused(_ paused: Bool) async
    /// Participant → host: report handsfree/earphone (`true`) vs speaker (`false`) for card color.
    func reportAudioRoute(isHandsfree: Bool) async
    func refreshConnection() async
    func listenAll() async
    func logoutAll() async
    /// Host-only: remove (kick) a single participant from the meeting.
    func removeParticipant(id: String) async
    /// Host-only: force that participant to pause listening (card orange).
    func unlistenParticipant(id: String) async
    /// Host-only: force that participant to resume listening (card green).
    func listenParticipant(id: String) async
    /// Host-only: broadcasts a short status message to every participant
    /// (implemented via the SDK's meeting chat channel — see `sendChatMsg:`).
    func sendStatusToAll(_ message: String) async
    /// Host-only: tells every participant to hide the status banner (Android parity).
    func removeStatusFromAll() async
    /// Keeps Zoom's built-in meeting / JBH waiting UI hidden while SwiftUI drives the flow.
    func suppressNativeMeetingUI() async
    func deinitialize() async
}
