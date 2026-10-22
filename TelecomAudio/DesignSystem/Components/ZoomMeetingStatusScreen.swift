//
//  ZoomMeetingStatusScreen.swift
//  Learning
//
//  Shared Android-style connect / disconnect status screen (light + dark).
//

import SwiftUI

enum ZoomMeetingStatusKind: Equatable {
    case connecting
    case disconnecting
}

/// Full-screen centered status card used for connect + disconnect flows.
struct ZoomMeetingStatusScreen: View {
    let kind: ZoomMeetingStatusKind
    let title: String
    let subtitle: String
    var toast: String? = nil
    /// 0...1 fill for connecting progress; `nil` hides the bar (disconnect).
    var progress: Double? = nil
    var onRetry: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var showsFailureButtons: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColors.screenBackground
                .ignoresSafeArea()

            diagonalTexture
                .allowsHitTesting(false)

            statusCard
                .padding(.horizontal, 28)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if let toast {
                    TelecomToastBanner(text: toast)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showsFailureButtons {
                    HStack(spacing: 16) {
                        Button("Cancel") { onCancel?() }
                        Button("Retry") { onRetry?() }
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.bottom, 8)
                }

                Text("Powered by Zoom")
                    .font(AppFonts.caption(13))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.bottom, 28)
            }
        }
    }

    private var diagonalTexture: some View {
        VStack(spacing: 18) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle()
                    .fill(AppColors.border.opacity(colorScheme == .dark ? 0.45 : 0.55))
                    .frame(height: 1)
                    .rotationEffect(.degrees(-8))
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 70)
    }

    private var statusCard: some View {
        VStack(spacing: 18) {
            statusIcon
                .padding(.top, 4)

            Text(title)
                .font(AppFonts.headline(22))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(AppFonts.body(14))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if let progress {
                progressBar(fill: min(max(progress, 0), 1))
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.statusCardCorner, style: .continuous))
        .shadow(
            color: .black.opacity(AppColors.cardShadowOpacity(for: colorScheme)),
            radius: 12,
            y: 5
        )
    }

    private var statusIcon: some View {
        let core = kind == .disconnecting
            ? AppColors.textMuted
            : AppColors.primaryButtonBackground
        let ring = kind == .disconnecting
            ? AppColors.textMuted.opacity(0.35)
            : AppColors.primaryButtonBackground.opacity(colorScheme == .dark ? 0.35 : 0.22)

        return ZStack {
            Circle()
                .stroke(ring, lineWidth: 7)
                .frame(width: 78, height: 78)
            Circle()
                .stroke(ring.opacity(1.2), lineWidth: 6)
                .frame(width: 52, height: 52)
            Circle()
                .fill(core)
                .frame(width: 18, height: 18)
        }
    }

    private func progressBar(fill: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.progressInactive)
                    .frame(height: 7)

                // Two-tone active fill like Android (short + long segment).
                HStack(spacing: 5) {
                    Capsule()
                        .fill(AppColors.primaryButtonBackground)
                        .frame(width: max(10, width * fill * 0.18), height: 7)
                    Capsule()
                        .fill(AppColors.primaryButtonBackground)
                        .frame(width: max(0, width * fill * 0.82 - 5), height: 7)
                }
                .frame(width: width * fill, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 7)
    }
}
