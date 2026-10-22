//
//  SessionManager.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol SessionManaging: AnyObject, Sendable {
    var isLoggedIn: Bool { get }
    var accessToken: String? { get }
    var username: String? { get }
    func saveSession(token: String, username: String) throws
    func clearSession()
    func logout()
    func isTokenValid() -> Bool
}

/// Stores auth token + username in Keychain only (never UserDefaults).
final class SessionManager: SessionManaging, @unchecked Sendable {
    static let shared = SessionManager()
    
    private let keychain: KeychainManaging
    private let tokenKey = "com.universal.telecomAudio.auth.accessToken"
    private let usernameKey = "com.universal.telecomAudio.auth.username"
    
    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedUsername: String?
    
    init(keychain: KeychainManaging = KeychainManager()) {
        self.keychain = keychain
        cachedToken = try? keychain.string(forKey: tokenKey)
        cachedUsername = try? keychain.string(forKey: usernameKey)
    }
    
    var isLoggedIn: Bool {
        isTokenValid()
    }
    
    var accessToken: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedToken
    }
    
    var username: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedUsername
    }
    
    func saveSession(token: String, username: String) throws {
        try keychain.set(token, forKey: tokenKey)
        try keychain.set(username, forKey: usernameKey)
        lock.lock()
        cachedToken = token
        cachedUsername = username
        lock.unlock()
    }
    
    func clearSession() {
        try? keychain.delete(forKey: tokenKey)
        try? keychain.delete(forKey: usernameKey)
        lock.lock()
        cachedToken = nil
        cachedUsername = nil
        lock.unlock()
    }
    
    func logout() {
        clearSession()
    }
    
    /// Validates JWT `exp` when present; otherwise treats non-empty token as valid.
    func isTokenValid() -> Bool {
        guard let token = accessToken, !token.isEmpty else { return false }
        guard let payload = Self.decodeJWTPayload(token) else {
            return true
        }
        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp) > Date()
        }
        if let expInt = payload["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(expInt)) > Date()
        }
        return true
    }
    
    private static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
