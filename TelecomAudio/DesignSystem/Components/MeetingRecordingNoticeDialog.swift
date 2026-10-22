//
//  MeetingRecordingNoticeDialog.swift
//  Learning
//

import SwiftUI

/// Local meeting recording notice — matches Leave Meeting / app card theme.
struct MeetingRecordingNoticeDialog: View {
    let onAcknowledge: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var infoColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black.opacity(0.75)
    }

    private var okBackground: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text("This meeting is being recorded.")
                        .font(AppFonts.body(15))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(infoColor)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)

                Button(action: onAcknowledge) {
                    Text("OK")
                        .font(AppFonts.button(16))
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.primaryButtonForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(okBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
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
}
