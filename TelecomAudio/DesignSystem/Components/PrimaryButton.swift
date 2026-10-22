//
//  PrimaryButton.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(AppColors.primaryButtonForeground)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(title)
                        .font(AppFonts.button(17))
                }
            }
            .foregroundStyle(AppColors.primaryButtonForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppColors.primaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCorner, style: .continuous))
        }
        .disabled(!isEnabled || isLoading)
        .opacity((!isEnabled || isLoading) ? 0.7 : 1)
    }
}
