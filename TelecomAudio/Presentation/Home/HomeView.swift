//
//  HomeView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Replicates Android Home / Dashboard screenshot (light + dark themes).
struct HomeView: View {
    @StateObject var viewModel: HomeViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TelecomScreenLayout(headerHeightRatio: 0.5) {
            TelecomHeader(logoSize: 110, bottomPadding: 35)
                .padding(.top, 0)
        } card: {
            contentCard
        }
        .onAppear { viewModel.refresh() }
        .alert("Logout", isPresented: $viewModel.showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                Task { await viewModel.logout() }
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .overlay {
            if viewModel.isStartingMeeting {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView(viewModel.isParticipant ? "Joining meeting..." : "Starting meeting...")
                        .padding(24)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(viewModel.isParticipant ? "Unable to join meeting" : "Unable to start meeting", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var contentCard: some View {
        TelecomCard {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Welcome back")
                        .font(AppFonts.body(15))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(viewModel.username)
                        .font(AppFonts.headline(26))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .padding(.top, 32)
                .padding(.bottom, 28)

                VStack(spacing: 14) {
                    PrimaryButton(
                        title: viewModel.isParticipant ? "Join Meeting" : "Start Meeting",
                        icon: "video.badge.plus"
                    ) {
                        Task { await viewModel.startMeeting() }
                    }

                    SecondaryButton(title: "Reset Password", icon: "lock.fill") {
                        viewModel.openResetPassword()
                    }

                    if !viewModel.isParticipant {
                        SecondaryButton(title: "Cloud Recordings", icon: "cloud.fill") {
                            viewModel.openCloudRecordings()
                        }
                    }

                    HStack(spacing: 14) {
                        squareAction(
                            title: "Recordings",
                            icon: "mic.fill",
                            border: AppColors.border,
                            foreground: AppColors.textPrimary
                        ) {
                            viewModel.openLocalRecordings()
                        }

                        squareAction(
                            title: "Logout",
                            icon: "rectangle.portrait.and.arrow.right",
                            border: AppColors.logoutBorder,
                            foreground: AppColors.logoutRed
                        ) {
                            viewModel.showLogoutConfirm = true
                        }
                    }
                    .padding(.top, 4)

                    VStack(spacing: 12) {
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(height: 1)
                            .padding(.horizontal, 40)
                        Text("Powered by Zoom SDK")
                            .font(AppFonts.caption(12))
                            .foregroundStyle(AppColors.textMuted)
                            .padding(.bottom, 18)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, AppSpacing.cardHorizontalInset)
            }
        }
    }

    private func squareAction(
        title: String,
        icon: String,
        border: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(title)
                    .font(AppFonts.button(14))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous)
                    .fill(AppColors.secondaryButtonBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous)
                    .stroke(border, lineWidth: 1.5)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
