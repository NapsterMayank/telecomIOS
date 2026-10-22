//
//  AuthRepository.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

final class AuthRepository: AuthRepositoryProtocol, @unchecked Sendable {
    private let authService: AuthServiceProtocol
    private let sessionManager: SessionManaging
    
    init(authService: AuthServiceProtocol, sessionManager: SessionManaging) {
        self.authService = authService
        self.sessionManager = sessionManager
    }
    
    func login(username: String, password: String) async throws -> LoginResponse {
        let response = try await authService.login(
            request: LoginRequest(username: username, password: password)
        )
        guard response.isSuccess, let token = response.token else {
            throw NetworkError.api(
                APIError(status: response.status, message: response.message ?? "Authentication failed")
            )
        }
        try sessionManager.saveSession(token: token, username: username)
        return response
    }
    
    func logout() {
        sessionManager.logout()
    }
}
