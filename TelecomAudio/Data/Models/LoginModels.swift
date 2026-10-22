//
//  LoginResponse.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

struct LoginRequest: Codable, Equatable {
    let username: String
    let password: String
}

/// Verified against live API: `POST https://telecom.ac/auth/login`
/// Success: `{"token":"<jwt>","status":"success"}`
/// Failure: `{"status":"error","message":"Authentication failed"}` (HTTP 401)
struct LoginResponse: Codable, Equatable {
    let token: String?
    let status: String?
    let message: String?
    
    var isSuccess: Bool {
        (status?.lowercased() == "success") && !(token ?? "").isEmpty
    }
}
