//
//  NetworkError.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

enum NetworkError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case noInternet
    case timeout
    case unauthorized
    case decodingFailed(String)
    case server(statusCode: Int, message: String?)
    case api(APIError)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Unexpected server response."
        case .noInternet:
            return "No internet connection."
        case .timeout:
            return "The request timed out."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .decodingFailed(let detail):
            return "Failed to parse server response. \(detail)"
        case .server(_, let message):
            return message ?? "Server error. Please try again."
        case .api(let error):
            return error.message
        case .unknown(let message):
            return message
        }
    }
}

struct APIError: Codable, Equatable, LocalizedError {
    let status: String?
    let message: String?
    let success: Bool?
    
    var errorDescription: String? { message }
    
    init(status: String? = nil, message: String?, success: Bool? = nil) {
        self.status = status
        self.message = message ?? "Something went wrong."
        self.success = success
    }
}
