//
//  APIClient.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

protocol APIClientProtocol: Sendable {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}

final class APIClient: APIClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let decoder: JSONDecoder
    private let onUnauthorized: (@Sendable () -> Void)?
    
    init(
        session: URLSession = .shared,
        requestBuilder: RequestBuilder,
        decoder: JSONDecoder = JSONDecoder(),
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.session = session
        self.requestBuilder = requestBuilder
        self.decoder = decoder
        self.onUnauthorized = onUnauthorized
    }
    
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let request = try requestBuilder.build(endpoint)
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw NetworkError.noInternet
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.unknown(urlError.localizedDescription)
            }
        }
        
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                if let decodedData = base64DecodedBody(from: data),
                   let decodedValue = try? decoder.decode(T.self, from: decodedData) {
                    return decodedValue
                }
                
                // Some endpoints (for example get-zoom-token) return an
                // unquoted plain-text value instead of a JSON document.
                if T.self == String.self,
                   let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty,
                   let typedValue = value as? T {
                    return typedValue
                }
                throw NetworkError.decodingFailed(error.localizedDescription)
            }
        case 401:
            onUnauthorized?()
            if let apiError: APIError = decodeJSONOrBase64(from: data) {
                throw NetworkError.api(apiError)
            }
            throw NetworkError.unauthorized
        default:
            if let apiError: APIError = decodeJSONOrBase64(from: data),
               let message = apiError.message {
                throw NetworkError.server(statusCode: http.statusCode, message: message)
            }
            let fallbackData = base64DecodedBody(from: data) ?? data
            let fallback = String(data: fallbackData, encoding: .utf8)
            throw NetworkError.server(statusCode: http.statusCode, message: fallback)
        }
    }
    
    private func decodeJSONOrBase64<T: Decodable>(from data: Data) -> T? {
        if let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        guard let decodedData = base64DecodedBody(from: data) else {
            return nil
        }
        return try? decoder.decode(T.self, from: decodedData)
    }
    
    private func base64DecodedBody(from data: Data) -> Data? {
        let encodedValue: String
        
        if let jsonString = try? decoder.decode(String.self, from: data) {
            encodedValue = jsonString
        } else if let rawString = String(data: data, encoding: .utf8) {
            encodedValue = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }
        
        guard !encodedValue.isEmpty else {
            return nil
        }
        
        var normalized = encodedValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let missingPadding = (4 - normalized.count % 4) % 4
        normalized.append(String(repeating: "=", count: missingPadding))
        return Data(base64Encoded: normalized)
    }
}
