//
//  ProfileImageLoader.swift
//  Learning
//

import Foundation
import UIKit

/// Loads `/api/files/...` profile images using the same auth + device headers as APIClient.
enum ProfileImageLoader {
    static func load(
        url: URL,
        sessionManager: SessionManaging,
        deviceInfo: DeviceInfoProvider
    ) async -> UIImage? {
        guard sessionManager.accessToken != nil else { return nil }

        let requestBuilder = RequestBuilder(
            baseURL: AppEnvironment.apiBaseURL,
            deviceInfo: deviceInfo,
            sessionManager: sessionManager
        )

        do {
            let request = try authenticatedFileRequest(for: url, requestBuilder: requestBuilder)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func authenticatedFileRequest(
        for url: URL,
        requestBuilder: RequestBuilder
    ) throws -> URLRequest {
        if let host = url.host,
           host == AppEnvironment.apiBaseURL.host {
            return try requestBuilder.build(
                APIEndpoint(
                    path: url.path,
                    method: .get,
                    requiresAuth: true,
                    headers: ["User-Agent": "iphone"]
                )
            )
        }

        // Fallback for unexpected absolute URLs.
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.timeoutInterval = 30
        request.setValue("iphone", forHTTPHeaderField: "User-Agent")
        if let token = requestBuilder.sessionManager.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in requestBuilder.deviceInfo.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

/// Finds host/book profile image URLs in the zoom-token platform JSON (`userMap.profile`, etc.).
enum HostProfileImageURL {
    static func parse(from json: Any) -> URL? {
        guard let root = json as? [String: Any] else { return nil }

        var candidates: [String] = []
        if let ios = root["iOS"] as? [String: Any] {
            if let userMap = ios["userMap"] as? [String: Any] {
                candidates.append(contentsOf: extractImageStrings(from: userMap))
            }
            candidates.append(contentsOf: extractImageStrings(from: ios))
        }
        candidates.append(contentsOf: extractImageStrings(from: root))

        for raw in candidates {
            if let url = normalize(raw) { return url }
        }
        return nil
    }

    private static func extractImageStrings(from dict: [String: Any]) -> [String] {
        var results: [String] = []
        for (key, value) in dict {
            guard let string = value as? String else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalizedKey = key.lowercased().replacingOccurrences(of: "_", with: "")
            let looksLikeImageKey = normalizedKey == "profile"
                || normalizedKey.contains("profileimage")
                || normalizedKey.contains("profilepic")
                || normalizedKey.contains("avatar")
                || normalizedKey.contains("image")
                || normalizedKey.contains("photo")
                || normalizedKey.contains("picture")
                || normalizedKey.contains("book")
                || normalizedKey == "file"
                || normalizedKey.contains("fileurl")

            if looksLikeImageKey
                || trimmed.contains("/api/files/")
                || trimmed.contains("telecom.ac/api/files") {
                results.append(trimmed)
            }
        }
        return results
    }

    private static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.contains("/api/files/") {
            let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
            return URL(string: path, relativeTo: AppEnvironment.apiBaseURL)?.absoluteURL
        }
        return nil
    }
}
