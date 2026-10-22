//
//  HostUnavailableExit.swift
//  Learning
//

import Foundation

/// Android parity: show host-off toast, clean up session, then terminate the app.
@MainActor
enum HostUnavailableExit {
    private static let toastVisibleDuration: UInt64 = 2_000_000_000

    static func handle(
        router: AppRouter,
        authRepository: AuthRepositoryProtocol,
        meetingCleanup: (@MainActor () async -> Void)? = nil
    ) {
        router.presentToast(HostJoinAvailability.unavailableMessage)
        router.showLogin()

        Task {
            if let meetingCleanup {
                await meetingCleanup()
            }
            authRepository.logout()
            try? await Task.sleep(nanoseconds: toastVisibleDuration)
            terminate()
        }
    }

    private static func terminate() {
        exit(0)
    }
}
