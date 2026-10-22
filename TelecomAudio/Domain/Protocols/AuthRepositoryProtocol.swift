//
//  AuthRepositoryProtocol.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol AuthRepositoryProtocol: Sendable {
    func login(username: String, password: String) async throws -> LoginResponse
    func logout()
}
