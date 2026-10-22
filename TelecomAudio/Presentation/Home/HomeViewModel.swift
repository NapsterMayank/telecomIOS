//
//  HomeViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var username: String = ""
    @Published private(set) var isParticipant = false
    @Published var isStartingMeeting = false
    @Published var errorMessage: String?
    @Published var showLogoutConfirm = false

    private let sessionManager: SessionManaging
    private let authRepository: AuthRepositoryProtocol
    private let zoomRepository: ZoomRepositoryProtocol
    private let meetingService: AudioMeetingServiceProtocol
    private let router: AppRouter

    init(
        sessionManager: SessionManaging,
        authRepository: AuthRepositoryProtocol,
        zoomRepository: ZoomRepositoryProtocol,
        meetingService: AudioMeetingServiceProtocol,
        router: AppRouter
    ) {
        self.sessionManager = sessionManager
        self.authRepository = authRepository
        self.zoomRepository = zoomRepository
        self.meetingService = meetingService
        self.router = router
        self.username = sessionManager.username ?? ""
    }

    func refresh() {
        username = sessionManager.username ?? ""
        if !sessionManager.isLoggedIn {
            router.showLogin()
            return
        }
        Task { await loadMeetingRole() }
    }

    private func loadMeetingRole() async {
        do {
            let credentials = try await zoomRepository.fetchZoomToken()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isParticipant = !credentials.isHost
            }
        } catch {
            // Keep host UI when role cannot be resolved.
        }
    }

    func startMeeting() async {
        errorMessage = nil
        isStartingMeeting = true
        defer { isStartingMeeting = false }

        do {
            let credentials = try await zoomRepository.fetchZoomToken()

            if !credentials.isHost && !credentials.hostJoinAvailable {
                handleHostUnavailableLogout()
                return
            }

            router.startMeetingFlow(credentials: credentials)
        } catch let error as NetworkError {
            if case .unauthorized = error {
                authRepository.logout()
                router.showLogin()
                return
            }
            if case .api(let apiError) = error, isHostUnavailableMessage(apiError.message) {
                handleHostUnavailableLogout()
                return
            }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleHostUnavailableLogout() {
        HostUnavailableExit.handle(
            router: router,
            authRepository: authRepository,
            meetingCleanup: { [self] in await meetingService.deinitialize() }
        )
    }

    private func isHostUnavailableMessage(_ message: String?) -> Bool {
        let lower = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return lower.contains("switchoff")
            || lower.contains("switch off")
            || lower.contains("not available")
            || lower.contains("host is not")
    }

    func openResetPassword() {
        router.showResetPassword()
    }

    func openCloudRecordings() {
        router.showCloudRecordings()
    }

    func openLocalRecordings() {
        router.showLocalRecordingsList()
    }

    func logout() async {
        await meetingService.deinitialize()
        authRepository.logout()
        router.showLogin()
    }
}
