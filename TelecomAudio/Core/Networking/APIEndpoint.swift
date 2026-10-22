//
//  APIEndpoint.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let requiresAuth: Bool
    let headers: [String: String]
    let queryItems: [URLQueryItem]
    let body: Data?
    
    init(
        path: String,
        method: HTTPMethod = .get,
        requiresAuth: Bool = true,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
    }
}

enum TelecomAPI {
    static func login(body: Data) -> APIEndpoint {
        APIEndpoint(
            path: "/auth/login",
            method: .post,
            requiresAuth: false,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }
    
    static var zoomToken: APIEndpoint {
        APIEndpoint(
            path: "/api/zooms/get-zoom-token",
            method: .get,
            requiresAuth: true,
            headers: ["User-Agent": "iphone"]
        )
    }
    
    static var cloudRecordings: APIEndpoint {
        APIEndpoint(
            path: "/api/zooms/sub_host/recordings",
            method: .get,
            requiresAuth: true
        )
    }
    
    /// MAP_ENDPOINT: Replace path when the Android reset-password API is confirmed.
    static func resetPassword(body: Data) -> APIEndpoint {
        APIEndpoint(
            path: "/api/users/update-password",
            method: .put,
            requiresAuth: true,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }
}

