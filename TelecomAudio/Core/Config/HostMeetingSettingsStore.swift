//
//  HostMeetingSettingsStore.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

/// Persists the "Settings" dialog options on the host meeting screen.
/// UserDefaults-backed (not Keychain) since none of these are secrets.
@MainActor
final class HostMeetingSettingsStore: ObservableObject {
    static let recordingSystemOptions = [
        "Option 1", "Option 2", "Option 3", "Option 4", "Option 5", "Option 6"
    ]
    
    /// When enabled, the currently-speaking participant's card is moved to the top of the grid.
    @Published var usersShuffling: Bool {
        didSet { defaults.set(usersShuffling, forKey: Keys.usersShuffling) }
    }
    /// When enabled, each participant card shows its network signal indicator.
    @Published var usersNetwork: Bool {
        didSet { defaults.set(usersNetwork, forKey: Keys.usersNetwork) }
    }
    @Published var recordingSystem: String {
        didSet { defaults.set(recordingSystem, forKey: Keys.recordingSystem) }
    }
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let usersShuffling = "com.universal.telecomAudio.hostMeeting.usersShuffling"
        static let usersNetwork = "com.universal.telecomAudio.hostMeeting.usersNetwork"
        static let recordingSystem = "com.universal.telecomAudio.hostMeeting.recordingSystem"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Match Android host Settings defaults.
        usersShuffling = defaults.object(forKey: Keys.usersShuffling) as? Bool ?? true
        usersNetwork = defaults.object(forKey: Keys.usersNetwork) as? Bool ?? false
        recordingSystem = defaults.string(forKey: Keys.recordingSystem) ?? Self.recordingSystemOptions.last!
    }
}
