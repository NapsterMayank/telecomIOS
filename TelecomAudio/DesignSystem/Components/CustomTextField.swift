//
//  CustomTextField.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .username
    var isFocused: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextField(placeholder, text: $text)
            .multilineTextAlignment(.center)
            .font(AppFonts.body(16))
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.fieldFocusBorder)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
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
