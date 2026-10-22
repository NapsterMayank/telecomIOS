//
//  SirenManager.swift
//  TelecomAudio
//

import Combine
import Foundation
import Siren

/// Runs Siren's App Store version check; the prompt itself is `AppUpdateDialog`
/// because `UIAlertController` can't color individual buttons.
final class SirenManager: ObservableObject {
    static let shared = SirenManager()

    /// App Store version that's newer than the installed build, or `nil` when up to date / dismissed.
    @Published private(set) var availableVersion: String?

    private init() {}

    func checkForAppUpdates() {
        let siren = Siren.shared
        siren.rulesManager = RulesManager(
            globalRules: Rules(promptFrequency: .immediately, forAlertType: .none),
            showAlertAfterCurrentVersionHasBeenReleasedForDays: 0
        )
        siren.wail { [weak self] result in
            let version = try? result.get().model.version
            DispatchQueue.main.async {
                self?.availableVersion = version
            }
        }
    }

    func updateNow() {
        Siren.shared.launchAppStore()
    }

    func remindNextTime() {
        availableVersion = nil
    }
}
