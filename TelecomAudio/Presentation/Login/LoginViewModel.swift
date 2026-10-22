//
//  LoginViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authRepository: AuthRepositoryProtocol
    private let router: AppRouter

    init(authRepository: AuthRepositoryProtocol, router: AppRouter) {
        self.authRepository = authRepository
        self.router = router
        let saved = SavedLoginCredentials.load()
        username = saved.username
        password = saved.password
    }

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isLoading
    }

    func login() async {
        errorMessage = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your credentials to continue"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authRepository.login(username: user, password: password)
            SavedLoginCredentials.save(username: user, password: password)
            router.showHome()
        } catch let error as NetworkError {
            errorMessage = error.errorDescription ?? "Authentication failed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Last successful login, kept in the Keychain so the fields stay filled after logout.
private enum SavedLoginCredentials {
    private static let keychain = KeychainManager()
    private static let usernameKey = "com.universal.telecomAudio.login.username"
    private static let passwordKey = "com.universal.telecomAudio.login.password"

    static func load() -> (username: String, password: String) {
        let username = (try? keychain.string(forKey: usernameKey)) ?? ""
        let password = (try? keychain.string(forKey: passwordKey)) ?? ""
        return (username, password)
    }

    static func save(username: String, password: String) {
        try? keychain.set(username, forKey: usernameKey)
        try? keychain.set(password, forKey: passwordKey)
    }
}
