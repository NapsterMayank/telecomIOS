//
//  LoginView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Matches Android login: TELECOM branding in the header band, compact Account Login card below.
struct LoginView: View {
    @StateObject var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field {
        case username, password
    }

    var body: some View {
        TelecomScreenLayout(headerHeightRatio: 0.47) {
            TelecomHeader(logoSize: 110, bottomPadding: 50)
                .padding(.top, 0)
        } card: {
            loginCard
        }
        // Plain tap (not simultaneous): taps landing on a field must reach the field
        // instead of racing it and clearing focus.
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var loginCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Account Login")
                    .font(AppFonts.headline(22))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Enter your credentials to continue")
                    .font(AppFonts.caption(14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 16) {
                CustomTextField(
                    placeholder: "Username",
                    text: $viewModel.username,
                    isFocused: focusedField == .username
                )
                .frame(width: AppSpacing.loginFieldWidth)
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

                SecureInputField(
                    placeholder: "Password",
                    text: $viewModel.password,
                    isFocused: focusedField == .password
                )
                .frame(width: AppSpacing.loginFieldWidth)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    Task { await viewModel.login() }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.caption(13))
                        .foregroundStyle(AppColors.logoutRed)
                        .multilineTextAlignment(.center)
                        .frame(width: AppSpacing.loginFieldWidth)
                }

                PrimaryButton(
                    title: "Login",
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canSubmit
                ) {
                    Task { await viewModel.login() }
                }
                .frame(width: AppSpacing.loginFieldWidth)
            }
            .padding(.bottom, AppSpacing.loginCardBottomInset)
        }
        .frame(width: AppSpacing.loginCardWidth)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.loginCardCorner, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .shadow(
            color: .black.opacity(AppColors.cardShadowOpacity(for: colorScheme)),
            radius: colorScheme == .dark ? 16 : 15,
            x: 0,
            y: 6
        )
    }
}
