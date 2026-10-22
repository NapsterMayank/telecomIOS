//
//  LocalRecordingRowView.swift
//  Learning
//

import SwiftUI

/// Android-style local recording row: note · name/size · trash.
struct LocalRecordingRowView: View {
    let file: LocalRecordingFile
    let isActive: Bool
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var noteColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.textPrimary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onTogglePlayback) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isActive && isPlaying ? "pause.fill" : "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(noteColor)
                        .frame(width: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.fileName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(file.sizeText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.muteRed)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
