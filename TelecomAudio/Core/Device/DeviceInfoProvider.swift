//
//  DeviceInfoProvider.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import UIKit

protocol DeviceInfoProviding: Sendable {
    var platform: String { get }
    var uuid: String { get }
    var model: String { get }
    var manufacturer: String { get }
    var userAgent: String { get }
    var commonHeaders: [String: String] { get }
}

/// Generates and persists a stable per-install device UUID in Keychain.
final class DeviceInfoProvider: DeviceInfoProviding, @unchecked Sendable {
    private let keychain: KeychainManaging
    private let uuidKey = "com.universal.telecomAudio.device.uuid"
    
    init(keychain: KeychainManaging) {
        self.keychain = keychain
    }
    
    var platform: String { "ios" }
    
    var manufacturer: String { "Apple" }
    
    var userAgent: String { "ios" }
    
    var uuid: String {
        if let existing = try? keychain.string(forKey: uuidKey), !existing.isEmpty {
            return existing
        }
        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        try? keychain.set(generated, forKey: uuidKey)
        return generated
    }
    
    var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return mapToMarketingName(identifier)
    }
    
    var commonHeaders: [String: String] {
        [
            "x-device-platform": platform,
            "x-device-uuid": uuid,
            "x-device-model": model,
            "x-device-manufacturer": manufacturer
        ]
    }
    
    private func mapToMarketingName(_ identifier: String) -> String {
        // Prefer human-readable model; fall back to machine identifier.
        let deviceModel = UIDevice.current.model
        if identifier.isEmpty {
            return deviceModel
        }
        return identifier
    }
}
