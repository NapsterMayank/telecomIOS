//
//  AppEnvironment.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

/// Resolves API base URL and environment name from Info.plist / xcconfig.
enum AppEnvironment {
    static var apiBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: raw),
           !raw.isEmpty {
            return url
        }
        // Fallback matches production host used by the Android app.
        return URL(string: "https://telecom.ac")!
    }
    
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "APP_ENVIRONMENT") as? String) ?? "Production"
    }
}
