//
//  LocalMeetingSettingsStore.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

/// Persists the "Settings" sheet options on the participant local-meeting
/// screen. Deliberately UserDefaults-backed (not Keychain) since none of
/// these are secrets — matches `SessionManager`'s doc comment that auth
/// material only ever goes in Keychain.
@MainActor
final class LocalMeetingSettingsStore: ObservableObject {
    static let recordingSystemOptions = (1...10).map { "Option \($0)" }

    @Published var unmuteWithIndicator: Bool {
        didSet { defaults.set(unmuteWithIndicator, forKey: Keys.unmuteWithIndicator) }
    }
    @Published var unmuteWithTouch: Bool {
        didSet { defaults.set(unmuteWithTouch, forKey: Keys.unmuteWithTouch) }
    }
    @Published var hostNetworkIndicator: Bool {
        didSet { defaults.set(hostNetworkIndicator, forKey: Keys.hostNetworkIndicator) }
    }
    @Published var recordingSystem: String {
        didSet { defaults.set(recordingSystem, forKey: Keys.recordingSystem) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let unmuteWithIndicator = "com.universal.telecomAudio.localMeeting.unmuteWithIndicator"
        static let unmuteWithTouch = "com.universal.telecomAudio.localMeeting.unmuteWithTouch"
        static let hostNetworkIndicator = "com.universal.telecomAudio.localMeeting.hostNetworkIndicator"
        static let recordingSystem = "com.universal.telecomAudio.localMeeting.recordingSystem"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unmuteWithIndicator = defaults.object(forKey: Keys.unmuteWithIndicator) as? Bool ?? false
        unmuteWithTouch = defaults.object(forKey: Keys.unmuteWithTouch) as? Bool ?? false
        hostNetworkIndicator = defaults.object(forKey: Keys.hostNetworkIndicator) as? Bool ?? true
        recordingSystem = defaults.string(forKey: Keys.recordingSystem) ?? Self.recordingSystemOptions.last!
    }
}
