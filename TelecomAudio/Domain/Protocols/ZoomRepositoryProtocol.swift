//
//  ZoomRepositoryProtocol.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol ZoomRepositoryProtocol: Sendable {
    func fetchZoomToken() async throws -> ZoomMeetingCredentials
}
