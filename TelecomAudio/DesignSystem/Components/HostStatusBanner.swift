//
//  HostStatusBanner.swift
//  Learning
//

import SwiftUI

/// Android-style red status strip. Host may show a trailing X to clear + broadcast;
/// participants only see the message until the host removes it.
struct HostStatusBanner: View {
    let message: String
    var showsDismissButton: Bool = true
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(AppFonts.bodyBold(15))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsDismissButton, let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(red: 183 / 255, green: 28 / 255, blue: 28 / 255))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
