//
//  ZoomInitializationViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

enum ZoomInitPhase: Equatable {
    case preparing
    case initializing
    case success
    case connecting
    case failed(String)

    var title: String {
        switch self {
        case .failed:
            return "Meeting connection failed"
        default:
            return "Connecting to meeting..."
        }
    }

    var subtitle: String {
        switch self {
        case .preparing:
            return "Preparing secure audio session..."
        case .initializing:
            return "Initializing Zoom SDK..."
        case .success:
            return "Zoom SDK initialized successfully"
        case .connecting:
            return "Preparing secure audio session..."
        case .failed(let message):
            return message
        }
    }

    var toast: String? {
        switch self {
        case .success, .connecting:
            return "Zoom SDK initialized successfully"
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    /// 0...1 progress fill (Android segmented bar).
    var progress: Double {
        switch self {
        case .preparing: return 0.28
        case .initializing: return 0.52
        case .success: return 0.78
        case .connecting: return 0.92
        case .failed: return 0.4
        }
    }
}

@MainActor
final class ZoomInitializationViewModel: ObservableObject {
    @Published var phase: ZoomInitPhase = .preparing

    private let credentials: ZoomMeetingCredentials
    private let meetingService: AudioMeetingServiceProtocol
    private let authRepository: AuthRepositoryProtocol
    private let router: AppRouter
    private var hostUnavailableHandled = false

    init(
        credentials: ZoomMeetingCredentials,
        meetingService: AudioMeetingServiceProtocol,
        authRepository: AuthRepositoryProtocol,
        router: AppRouter
    ) {
        self.credentials = credentials
        self.meetingService = meetingService
        self.authRepository = authRepository
        self.router = router
    }

    func start() async {
        meetingService.onHostUnavailable = { [weak self] in
            Task { @MainActor in
                await self?.handleHostUnavailableAndLogout()
            }
        }

        phase = .preparing
        try? await Task.sleep(nanoseconds: 450_000_000)

        do {
            phase = .initializing
            try await meetingService.initializeSDK(with: credentials)
            phase = .success
            try? await Task.sleep(nanoseconds: 700_000_000)

            phase = .connecting
            try await meetingService.joinMeeting(with: credentials)

            if credentials.isHost {
                router.showMeeting()
                return
            }

            switch meetingService.connectionState {
            case .connected:
                router.showLocalRecordings()
            case .waitingForHost, .connecting:
                // Zoom never reached in-meeting — host line is off (Android parity).
                await handleHostUnavailableAndLogout()
            default:
                if !credentials.hostJoinAvailable {
                    await handleHostUnavailableAndLogout()
                } else {
                    router.showLocalRecordings()
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func handleHostUnavailableAndLogout() async {
        guard !hostUnavailableHandled else { return }
        hostUnavailableHandled = true
        HostUnavailableExit.handle(
            router: router,
            authRepository: authRepository,
            meetingCleanup: { [self] in
                await meetingService.leaveMeeting()
                await meetingService.deinitialize()
            }
        )
    }

    func retry() {
        Task { await start() }
    }

    func cancel() {
        Task {
            await meetingService.deinitialize()
            router.showHome()
        }
    }
}
