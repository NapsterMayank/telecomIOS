//
//  CloudRecordingsViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine

@MainActor
final class CloudRecordingsViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case empty
        case loaded([CloudRecordingItem])
        case failed(String)
    }

    @Published var state: LoadState = .loading

    private let repository: RecordingsRepositoryProtocol
    private let router: AppRouter

    init(repository: RecordingsRepositoryProtocol, router: AppRouter) {
        self.repository = repository
        self.router = router
    }

    func load() async {
        state = .loading
        do {
            let items = try await repository.fetchCloudRecordings()
            state = items.isEmpty ? .empty : .loaded(items)
        } catch let error as NetworkError {
            if case .unauthorized = error {
                state = .failed("Your session has expired. Please sign in again.")
                router.showLogin()
                return
            }
            state = .failed(error.errorDescription ?? "Failed to load recordings")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func back() {
        router.dismissCloudRecordings()
        if router.state == .recordings {
            router.showHome()
        }
    }
}
