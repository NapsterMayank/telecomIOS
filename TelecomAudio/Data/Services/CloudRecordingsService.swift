//
//  CloudRecordingsService.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol CloudRecordingsServiceProtocol: Sendable {
    func fetchRecordings() async throws -> CloudRecordingsResponse
}

final class CloudRecordingsService: CloudRecordingsServiceProtocol, @unchecked Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchRecordings() async throws -> CloudRecordingsResponse {
        try await apiClient.request(TelecomAPI.cloudRecordings)
    }
}
