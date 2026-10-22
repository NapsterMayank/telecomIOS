//
//  RequestBuilder.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

struct RequestBuilder {
    let baseURL: URL
    let deviceInfo: DeviceInfoProvider
    let sessionManager: SessionManaging
    
    func build(_ endpoint: APIEndpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let trimmedPath = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components?.path = (baseURL.path == "/" ? "" : baseURL.path) + trimmedPath
        
        // When baseURL has no path, URLComponents.path should be the endpoint path.
        if baseURL.path.isEmpty || baseURL.path == "/" {
            components?.path = trimmedPath
        }
        
        if !endpoint.queryItems.isEmpty {
            components?.queryItems = endpoint.queryItems
        }
        
        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30
        request.httpBody = endpoint.body
        
        for (key, value) in deviceInfo.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if endpoint.requiresAuth {
            guard let token = sessionManager.accessToken, !token.isEmpty else {
                throw NetworkError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
}
