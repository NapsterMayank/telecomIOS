//
//  ZoomTokenService.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol ZoomTokenServiceProtocol: Sendable {
    func fetchZoomToken() async throws -> ZoomTokenResponse
}

final class ZoomTokenService: ZoomTokenServiceProtocol, @unchecked Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchZoomToken() async throws -> ZoomTokenResponse {
        let rawToken: String = try await apiClient.request(TelecomAPI.zoomToken)
        return try ZoomTokenResponse(rawToken: rawToken)
    }
}
