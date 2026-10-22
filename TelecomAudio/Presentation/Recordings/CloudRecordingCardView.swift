//
//  CloudRecordingCardView.swift
//  Learning
//
//  Android-matching Cloud Recordings modal + lavender/dark item cards.
//

import SwiftUI
import UIKit

struct CloudRecordingCardView: View {
    let item: CloudRecordingItem
    var onPlay: (() -> Void)?
    var onShare: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayTitle)
                .font(AppFonts.bodyBold(15))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                metaLabel(item.displayDate, icon: "calendar")

                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(item.displayDuration)
                        .font(AppFonts.caption(12))
                }
                .foregroundStyle(AppColors.cloudDurationText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppColors.cloudDurationBadge)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                metaLabel(item.displayTimeRange, icon: "clock")

                Spacer(minLength: 8)

                Button {
                    onPlay?()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.cloudMetaIcon)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.openURL == nil)
                .opacity(item.openURL == nil ? 0.35 : 1)

                Button {
                    onShare?()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.cloudMetaIcon)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.shareURL == nil)
                .opacity(item.shareURL == nil ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cloudRecordingCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.cloudMetaIcon)
            Text(text)
                .font(AppFonts.caption(13))
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

/// Theme-aware Cloud Recordings panel (light + dark) — Android modal with home visible at sides.
struct CloudRecordingsPanel: View {
    let state: CloudRecordingsViewModel.LoadState
    let onClose: () -> Void
    let onRetry: () -> Void
    let onPlay: (CloudRecordingItem) -> Void
    let onShare: (CloudRecordingItem) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Dim only — Home / Meeting stays visible around the card edges.
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Text("Cloud Recordings")
                    .font(AppFonts.headline(22))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 14)

                Group {
                    switch state {
                    case .loading:
                        ProgressView("Loading...")
                            .tint(AppColors.modalAccent)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .empty:
                        EmptyStateView(
                            title: "No Cloud Recordings",
                            message: "Cloud recordings will appear here."
                        )
                    case .loaded(let items):
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(items) { item in
                                    CloudRecordingCardView(
                                        item: item,
                                        onPlay: { onPlay(item) },
                                        onShare: { onShare(item) }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    case .failed(let message):
                        ErrorView(message: message, onRetry: onRetry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Text("Close")
                            .font(AppFonts.button(15))
                            .foregroundStyle(AppColors.primaryButtonForeground)
                            .padding(.horizontal, 28)
                            .frame(height: 44)
                            .background(AppColors.primaryButtonBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.45 : 0.2),
                radius: 18,
                y: 8
            )
            // Side / top / bottom insets so Home peeks through like Android.
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }
}

struct CloudSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

struct CloudActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
