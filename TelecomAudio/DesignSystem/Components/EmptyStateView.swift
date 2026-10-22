//
//  EmptyStateView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct EmptyStateView: View {
    var title: String = "Nothing here yet"
    var message: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textSecondary)
            Text(title)
                .font(AppFonts.bodyBold(17))
                .foregroundStyle(AppColors.textPrimary)
            if !message.isEmpty {
                Text(message)
                    .font(AppFonts.caption(14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
