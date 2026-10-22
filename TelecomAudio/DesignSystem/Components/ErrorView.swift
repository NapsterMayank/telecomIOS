//
//  ErrorView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct ErrorView: View {
    let message: String
    var retryTitle: String = "Retry"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textSecondary)
            Text(message)
                .font(AppFonts.body(15))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(AppFonts.button(15))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
