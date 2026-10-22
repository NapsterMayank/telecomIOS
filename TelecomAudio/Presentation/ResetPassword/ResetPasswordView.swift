//
//  ResetPasswordView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Android-style "Enter Password" modal over the dimmed home screen.
struct ResetPasswordView: View {
    @StateObject var viewModel: ResetPasswordViewModel
    @FocusState private var passwordFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(AppColors.modalAccent)
                    .padding(.top, 36)

                Text("Enter Password")
                    .font(AppFonts.headline(22))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.top, 22)

                SecureField("Password", text: $viewModel.password)
                    .font(AppFonts.body(17))
                    .foregroundStyle(AppColors.textPrimary)
                    .tint(AppColors.modalAccent)
                    .multilineTextAlignment(.leading)
                    .textContentType(.newPassword)
                    .submitLabel(.done)
                    .focused($passwordFocused)
                    .onSubmit {
                        Task { await viewModel.submit() }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(AppColors.fieldBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                passwordFocused ? AppColors.fieldFocusBorder : AppColors.fieldBorder,
                                lineWidth: passwordFocused ? 2 : 1.5
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 28)
                    .padding(.top, 28)

                HStack(spacing: 0) {
                    Button("Cancel") {
                        passwordFocused = false
                        viewModel.back()
                    }
                    .font(AppFonts.button(16))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)

                    Button {
                        passwordFocused = false
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(AppColors.modalAccent)
                        } else {
                            Text("Submit")
                                .fontWeight(.bold)
                        }
                    }
                    .font(AppFonts.button(16))
                    .foregroundStyle(AppColors.modalAccent)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isLoading)
                }
                .padding(.top, 36)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: min(geometry.size.width - 56, 360))
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(
                color: .black.opacity(AppColors.cardShadowOpacity(for: colorScheme)),
                radius: 20,
                y: 10
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: {
                    viewModel.errorMessage != nil || viewModel.successMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        clearAlert()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                clearAlert()
            }
        } message: {
            Text(viewModel.successMessage ?? viewModel.errorMessage ?? "")
        }
    }

    private var alertTitle: String {
        viewModel.successMessage == nil ? "Reset Password Failed" : "Success"
    }

    private func clearAlert() {
        let didSucceed = viewModel.successMessage != nil
        viewModel.errorMessage = nil
        viewModel.successMessage = nil
        if didSucceed {
            viewModel.back()
        }
    }
}
