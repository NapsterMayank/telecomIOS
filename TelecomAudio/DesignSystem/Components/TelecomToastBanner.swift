//
//  TelecomToastBanner.swift
//  Learning
//

import SwiftUI

/// Android-style bottom toast with TELECOM app logo (connect screen + global router toasts).
struct TelecomToastBanner: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image("logoImage")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            Text(text)
                .font(AppFonts.body(14))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.toastCorner, style: .continuous))
        .shadow(
            color: .black.opacity(AppColors.cardShadowOpacity(for: colorScheme)),
            radius: 10,
            y: 3
        )
    }
}
