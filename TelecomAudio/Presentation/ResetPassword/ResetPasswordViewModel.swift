//
//  ResetPasswordViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

@MainActor
final class ResetPasswordViewModel: ObservableObject {
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let service: ResetPasswordServiceProtocol
    private let router: AppRouter

    init(service: ResetPasswordServiceProtocol, router: AppRouter) {
        self.service = service
        self.router = router
    }

    func submit() async {
        errorMessage = nil
        successMessage = nil

        let newPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newPassword.isEmpty else {
            errorMessage = "Please enter a password."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await service.resetPassword(
                request: ResetPasswordRequest(password: newPassword)
            )
            if response.success == false || response.status?.lowercased() == "error" {
                errorMessage = response.message ?? "Unable to reset password."
                return
            }
            successMessage = "Password reset successfully"
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func back() {
        router.dismissResetPassword()
    }
}
