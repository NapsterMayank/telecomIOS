//
//  RecordingsRepositoryProtocol.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol RecordingsRepositoryProtocol: Sendable {
    func fetchCloudRecordings() async throws -> [CloudRecordingItem]
}
