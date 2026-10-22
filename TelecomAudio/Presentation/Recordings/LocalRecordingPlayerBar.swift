//
//  LocalRecordingPlayerBar.swift
//  Learning
//

import SwiftUI

/// Android-style in-list player: filename, seek, −10 / play / +10 / share / close.
struct LocalRecordingPlayerBar: View {
    let file: LocalRecordingFile
    @ObservedObject var controller: LocalRecordingPlaybackController
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 44 / 255, green: 44 / 255, blue: 48 / 255)
            : AppColors.namePillLavender
    }

    private var primaryText: Color {
        colorScheme == .dark ? AppColors.textPrimary : AppColors.black
    }

    private var controlColor: Color {
        colorScheme == .dark ? AppColors.textSecondary : AppColors.black
    }

    private var progressTint: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    private var playButtonFill: Color {
        colorScheme == .dark
            ? Color(red: 70 / 255, green: 70 / 255, blue: 76 / 255)
            : AppColors.participantMicGray
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(file.fileName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { controller.progress },
                        set: { controller.seek(toProgress: $0) }
                    )
                )
                .tint(progressTint)

                HStack {
                    Text(controller.formattedCurrentTime)
                    Spacer()
                    Text(controller.formattedTotalTime)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(controlColor)
            }

            HStack(spacing: 0) {
                Button {
                    controller.seek(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(controlColor)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(playButtonFill)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    controller.seek(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(controlColor)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(controlColor)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    controller.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(controlColor)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
