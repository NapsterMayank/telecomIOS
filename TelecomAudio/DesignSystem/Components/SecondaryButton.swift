//
//  SecondaryButton.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var borderColor: Color = AppColors.border
    var foreground: Color = AppColors.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(title)
                    .font(AppFonts.button(16))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppColors.secondaryButtonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
