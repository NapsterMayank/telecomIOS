//
//  ZoomRepository.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

final class ZoomRepository: ZoomRepositoryProtocol, @unchecked Sendable {
    private let zoomTokenService: ZoomTokenServiceProtocol
    private let sessionManager: SessionManaging

    init(zoomTokenService: ZoomTokenServiceProtocol, sessionManager: SessionManaging) {
        self.zoomTokenService = zoomTokenService
        self.sessionManager = sessionManager
    }

    func fetchZoomToken() async throws -> ZoomMeetingCredentials {
        let response = try await zoomTokenService.fetchZoomToken()
        let username = sessionManager.username ?? "User"
        return try ZoomMeetingCredentials.from(response: response, fallbackUsername: username)
    }
}
