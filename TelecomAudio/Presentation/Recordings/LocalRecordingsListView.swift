//
//  LocalRecordingsListView.swift
//  Learning
//

import SwiftUI

/// Standalone browser for on-device recordings saved under Documents/Recordings.
struct LocalRecordingsListView: View {
    @StateObject var viewModel: LocalRecordingsListViewModel

    var body: some View {
        LocalRecordingsPanel(
            isEmpty: viewModel.recordings.isEmpty,
            emptyMessage: "Recordings captured on this device will appear here.",
            canDeleteAll: !viewModel.recordings.isEmpty,
            groupedRecordings: viewModel.groupedRecordings,
            playback: viewModel.recordingPlayback,
            isPlaybackActive: viewModel.isPlaybackActive,
            isPlaybackPlaying: viewModel.isPlaybackPlaying,
            onTogglePlayback: viewModel.togglePlayback,
            onDelete: viewModel.requestDelete,
            onDeleteAll: viewModel.requestDeleteAll,
            onClose: { viewModel.back() },
            pendingDeletion: viewModel.recordingPendingDeletion,
            showDeleteAllConfirmation: viewModel.showDeleteAllConfirmation,
            onCancelDelete: viewModel.cancelDelete,
            onConfirmDelete: viewModel.confirmDelete,
            onCancelDeleteAll: viewModel.cancelDeleteAll,
            onConfirmDeleteAll: viewModel.confirmDeleteAll
        )
        .onAppear {
            viewModel.loadRecordings()
        }
    }
}
