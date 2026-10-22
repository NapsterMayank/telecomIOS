//
//  LocalRecordingsListViewModel.swift
//  Learning
//

import Combine
import Foundation

@MainActor
final class LocalRecordingsListViewModel: ObservableObject {
    @Published private(set) var recordings: [LocalRecordingFile] = []
    @Published var recordingPendingDeletion: LocalRecordingFile?
    @Published var showDeleteAllConfirmation = false

    private let recorder: LocalRecordingRecorder
    private let router: AppRouter
    private let playbackController = LocalRecordingPlaybackController()
    private var cancellables = Set<AnyCancellable>()

    var groupedRecordings: [(dateGroup: String, files: [LocalRecordingFile])] {
        LocalRecordingFile.grouped(from: recordings)
    }

    var recordingPlayback: LocalRecordingPlaybackController { playbackController }

    init(recorder: LocalRecordingRecorder? = nil, router: AppRouter) {
        self.recorder = recorder ?? .shared
        self.router = router
        playbackController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.recorder.onFilesChanged = { [weak self] in
            self?.loadRecordings()
        }
        loadRecordings()
    }

    func loadRecordings() {
        recordings = recorder.loadFiles()
    }

    func back() {
        playbackController.stop()
        router.dismissLocalRecordingsList()
        if router.state == .localRecordingsList {
            router.showHome()
        }
    }

    func togglePlayback(_ file: LocalRecordingFile) {
        playbackController.togglePlayback(for: file)
    }

    func isPlaybackActive(_ file: LocalRecordingFile) -> Bool {
        playbackController.isActive(file)
    }

    func isPlaybackPlaying(_ file: LocalRecordingFile) -> Bool {
        playbackController.isActive(file) && playbackController.isPlaying
    }

    func currentTimeText(for file: LocalRecordingFile) -> String? {
        playbackController.formattedCurrentTime(for: file)
    }

    func totalTimeText(for file: LocalRecordingFile) -> String? {
        playbackController.formattedTotalTime(for: file)
    }

    func requestDelete(_ file: LocalRecordingFile) {
        recordingPendingDeletion = file
    }

    func cancelDelete() {
        recordingPendingDeletion = nil
    }

    func confirmDelete() {
        guard let file = recordingPendingDeletion else { return }
        playbackController.stopIfPlaying(file)
        recorder.delete(file)
        recordingPendingDeletion = nil
        loadRecordings()
    }

    func deleteAll() {
        playbackController.stop()
        recorder.deleteAll()
        loadRecordings()
    }

    func requestDeleteAll() {
        showDeleteAllConfirmation = true
    }

    func cancelDeleteAll() {
        showDeleteAllConfirmation = false
    }

    func confirmDeleteAll() {
        showDeleteAllConfirmation = false
        deleteAll()
    }
}
