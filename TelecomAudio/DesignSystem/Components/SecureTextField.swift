//
//  SecureInputField.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPasswordVisible = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if isPasswordVisible {
                    TextField(placeholder, text: $text)
                        .textContentType(.password)
                } else {
                    SecureField(placeholder, text: $text)
                        .textContentType(.password)
                }
            }
            .multilineTextAlignment(.center)
            .font(AppFonts.body(16))
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.fieldFocusBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.leading, 16)
            .padding(.trailing, 44)

            Button {
                isPasswordVisible.toggle()
            } label: {
                // State icon: slash = hidden, open eye = visible (matches Android login).
                Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(AppColors.fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.fieldCorner, style: .continuous)
                .stroke(
                    isFocused ? AppColors.fieldFocusBorder : AppColors.fieldBorder,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.fieldCorner, style: .continuous))
        .shadow(
            color: .black.opacity(AppColors.fieldShadowOpacity(for: colorScheme)),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}
