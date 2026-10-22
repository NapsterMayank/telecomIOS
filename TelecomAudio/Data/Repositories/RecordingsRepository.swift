//
//  RecordingsRepository.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

final class RecordingsRepository: RecordingsRepositoryProtocol, @unchecked Sendable {
    private let service: CloudRecordingsServiceProtocol

    init(service: CloudRecordingsServiceProtocol) {
        self.service = service
    }

    func fetchCloudRecordings() async throws -> [CloudRecordingItem] {
        let response = try await service.fetchRecordings()
        return response.data ?? []
    }
}
