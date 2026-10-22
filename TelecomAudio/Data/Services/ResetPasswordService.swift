//
//  ResetPasswordService.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol ResetPasswordServiceProtocol: Sendable {
    func resetPassword(request: ResetPasswordRequest) async throws -> ResetPasswordResponse
}

/// Placeholder service — endpoint path is marked MAP_ENDPOINT in TelecomAPI.resetPassword.
final class ResetPasswordService: ResetPasswordServiceProtocol, @unchecked Sendable {
    private let apiClient: APIClientProtocol
    private let isEndpointConfigured: Bool

    init(apiClient: APIClientProtocol, isEndpointConfigured: Bool = false) {
        self.apiClient = apiClient
        self.isEndpointConfigured = isEndpointConfigured
    }

    func resetPassword(request: ResetPasswordRequest) async throws -> ResetPasswordResponse {
        guard isEndpointConfigured else {
            throw NetworkError.unknown(
                "Reset Password API is not configured yet. MAP_ENDPOINT: set TelecomAPI.resetPassword path and enable isEndpointConfigured."
            )
        }
        let body = try JSONEncoder().encode(request)
        return try await apiClient.request(TelecomAPI.resetPassword(body: body))
    }
}
