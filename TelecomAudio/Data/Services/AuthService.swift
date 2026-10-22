//
//  AuthServiceProtocol.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol AuthServiceProtocol: Sendable {
    func login(request: LoginRequest) async throws -> LoginResponse
}

final class AuthService: AuthServiceProtocol, @unchecked Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    func login(request: LoginRequest) async throws -> LoginResponse {
        let body = try JSONEncoder().encode(request)
        return try await apiClient.request(TelecomAPI.login(body: body))
    }
}
