//
//  AppUpdateDialog.swift
//  TelecomAudio
//

import SwiftUI

/// App Store update prompt — green "Update now", red "Next time".
struct AppUpdateDialog: View {
    let version: String
    let onUpdate: () -> Void
    let onNextTime: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.speakerGreen)
                    .padding(.top, 22)

                Text("Update Available")
                    .font(AppFonts.button(18))
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.top, 12)

                Text("A new version \(version) is available, want to update ?")
                    .font(AppFonts.body(15))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

               
                
                VStack(spacing: 10) {
                    dialogButton(" Yes, update now", background: AppColors.speakerGreen, action: onUpdate)
                    dialogButton("No, update later", background: AppColors.muteRed, action: onNextTime)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 340)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.45 : 0.22),
                radius: 20,
                y: 8
            )
            .padding(.horizontal, 36)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func dialogButton(_ title: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.button(16))
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
