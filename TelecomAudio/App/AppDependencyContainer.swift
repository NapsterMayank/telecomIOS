//
//  AppDependencyContainer.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

@MainActor
final class AppDependencyContainer: ObservableObject {
    let sessionManager: SessionManager
    let keychain: KeychainManager
    let deviceInfo: DeviceInfoProvider
    let apiClient: APIClient
    let authRepository: AuthRepository
    let zoomRepository: ZoomRepository
    let recordingsRepository: RecordingsRepository
    let resetPasswordService: ResetPasswordService
    let meetingService: AudioMeetingServiceProtocol

    init() {
        let keychain = KeychainManager()
        let sessionManager = SessionManager(keychain: keychain)
        let deviceInfo = DeviceInfoProvider(keychain: keychain)

        let requestBuilder = RequestBuilder(
            baseURL: AppEnvironment.apiBaseURL,
            deviceInfo: deviceInfo,
            sessionManager: sessionManager
        )

        let apiClient = APIClient(
            requestBuilder: requestBuilder,
            onUnauthorized: { [weak sessionManager] in
                sessionManager?.clearSession()
            }
        )

        let authService = AuthService(apiClient: apiClient)
        let zoomTokenService = ZoomTokenService(apiClient: apiClient)
        let recordingsService = CloudRecordingsService(apiClient: apiClient)

        self.keychain = keychain
        self.sessionManager = sessionManager
        self.deviceInfo = deviceInfo
        self.apiClient = apiClient
        self.authRepository = AuthRepository(authService: authService, sessionManager: sessionManager)
        self.zoomRepository = ZoomRepository(zoomTokenService: zoomTokenService, sessionManager: sessionManager)
        self.recordingsRepository = RecordingsRepository(service: recordingsService)
        self.resetPasswordService = ResetPasswordService(apiClient: apiClient, isEndpointConfigured: true)
        self.meetingService = ZoomAudioMeetingService()
    }
}
