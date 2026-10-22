//
//  LocalRecordingsSheetContent.swift
//  Learning
//

import SwiftUI

/// Android-matching local recordings list: date headers + note/name/size/trash rows.
struct LocalRecordingsSheetContent: View {
    let groupedRecordings: [(dateGroup: String, files: [LocalRecordingFile])]
    @ObservedObject var playback: LocalRecordingPlaybackController
    let isPlaybackActive: (LocalRecordingFile) -> Bool
    let isPlaybackPlaying: (LocalRecordingFile) -> Bool
    let onTogglePlayback: (LocalRecordingFile) -> Void
    let onDelete: (LocalRecordingFile) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var dateHeaderColor: Color {
        colorScheme == .dark ? AppColors.textSecondary : AppColors.textPrimary
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedRecordings, id: \.dateGroup) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.dateGroup)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(dateHeaderColor)
                                .padding(.top, 4)

                            ForEach(group.files) { file in
                                LocalRecordingRowView(
                                    file: file,
                                    isActive: isPlaybackActive(file),
                                    isPlaying: isPlaybackPlaying(file),
                                    onTogglePlayback: { onTogglePlayback(file) },
                                    onDelete: { onDelete(file) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            }

            if let file = playback.playingFile {
                LocalRecordingPlayerBar(file: file, controller: playback)
            }
        }
        .alert(
            "Playback Failed",
            isPresented: Binding(
                get: { playback.lastErrorMessage != nil },
                set: { if !$0 { playback.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                playback.clearError()
            }
        } message: {
            Text(playback.lastErrorMessage ?? "Unable to play this recording.")
        }
    }
}

/// Android-style Recordings modal: title + Delete All + X, theme-aware card.
struct LocalRecordingsPanel: View {
    let isEmpty: Bool
    let emptyMessage: String
    let canDeleteAll: Bool
    let groupedRecordings: [(dateGroup: String, files: [LocalRecordingFile])]
    @ObservedObject var playback: LocalRecordingPlaybackController
    let isPlaybackActive: (LocalRecordingFile) -> Bool
    let isPlaybackPlaying: (LocalRecordingFile) -> Bool
    let onTogglePlayback: (LocalRecordingFile) -> Void
    let onDelete: (LocalRecordingFile) -> Void
    let onDeleteAll: () -> Void
    let onClose: () -> Void

    let pendingDeletion: LocalRecordingFile?
    let showDeleteAllConfirmation: Bool
    let onCancelDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDeleteAll: () -> Void
    let onConfirmDeleteAll: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var closeButtonBackground: Color {
        AppColors.primaryButtonBackground
    }

    private var closeButtonForeground: Color {
        AppColors.primaryButtonForeground
    }

    var body: some View {
        ZStack {
            // Android: dimmed home/meeting behind the card (sides stay visible).
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()
                .onTapGesture {
                    guard pendingDeletion == nil, !showDeleteAllConfirmation else { return }
                    onClose()
                }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Recordings")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Button("Delete All", action: onDeleteAll)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.muteRed)
                            .disabled(!canDeleteAll)
                            .opacity(canDeleteAll ? 1 : 0.35)

                        Spacer(minLength: 8)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(closeButtonForeground)
                                .frame(width: 30, height: 30)
                                .background(closeButtonBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                    Group {
                        if isEmpty {
                            EmptyStateView(
                                title: "No Recordings Available",
                                message: emptyMessage
                            )
                        } else {
                            LocalRecordingsSheetContent(
                                groupedRecordings: groupedRecordings,
                                playback: playback,
                                isPlaybackActive: isPlaybackActive,
                                isPlaybackPlaying: isPlaybackPlaying,
                                onTogglePlayback: onTogglePlayback,
                                onDelete: onDelete
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.45 : 0.2),
                    radius: 18,
                    y: 8
                )
                // Side insets so Home / Meeting stays visible around the card.
                .padding(.horizontal, 18)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .contentShape(Rectangle())
            }

            if pendingDeletion != nil {
                LocalRecordingsDeleteDialog(
                    title: "Delete Recording",
                    message: "Are you sure you want to delete this recording?",
                    confirmTitle: "Delete",
                    onCancel: onCancelDelete,
                    onConfirm: onConfirmDelete
                )
                .zIndex(20)
            } else if showDeleteAllConfirmation {
                LocalRecordingsDeleteDialog(
                    title: "Delete All Recordings",
                    message: "Are you sure you want to delete all recordings? This cannot be undone.",
                    confirmTitle: "Delete All",
                    onCancel: onCancelDeleteAll,
                    onConfirm: onConfirmDeleteAll
                )
                .zIndex(20)
            }
        }
    }
}

/// Android Material-style delete confirm — Cancel (accent) + Delete (red).
private struct LocalRecordingsDeleteDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var cancelColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.textPrimary
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 28) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(cancelColor)
                    Button(confirmTitle, action: onConfirm)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.muteRed)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 320)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .padding(.horizontal, 28)
        }
    }
}
