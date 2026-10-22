//
//  ZoomTokenResponse.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

/// Supports both the live endpoint's Base64-encoded platform payload and legacy JSON responses.

struct ZoomTokenResponse: Decodable, Equatable {
    let status: String?
    let success: Bool?
    let message: String?
    let token: String?
    let zak: String?
    let sdkToken: String?
    let jwt: String?
    let signature: String?
    let sdkKey: String?
    let meetingNumber: String?
    let meetingId: String?
    let password: String?
    let passcode: String?
    let userName: String?
    let userId: String?
    let expiry: String?
    let expiryDate: String?
    let expiresAt: String?
    let expiresInDays: Int?
    let data: ZoomTokenData?
    
    enum CodingKeys: String, CodingKey {
        case status, success, message, token, zak
        case sdkToken, jwt, signature, sdkKey
        case meetingNumber, meetingId, password, passcode
        case userName, userId
        case expiry, expiryDate, expiresAt, expiresInDays
        case data
        // Common alternate keys from backends
        case meeting_number
        case meeting_id
        case zoom_token
        case access_token
        case expire_date
        case expireDate
    }
    
    /// Role parsed from the platform payload (host starts a meeting, participant joins one).
    let role: ZoomRole?
    /// Participant may join only when the host has started / line is on (from platform payload).
    let hostJoinAvailable: Bool
    /// Host/book profile image from `userMap.profile` → `/api/files/...` (website parity).
    let profileImageURL: URL?
    /// Book owner / host display name from `userMap` (e.g. `username`, `bookName`).
    let bookOwnerName: String?
    /// Value of the `book name` field. Preferred over `username` for the participant pill.
    let bookName: String?
    let banner:String?
    /// Value of the `client message` field, shown under the participant avatar.
    let clientMessage: String?
    /// `userMap.username`, kept when the backend sends it as a number.
    let accountUsername: String?
    /// Host Zoom subscription — show payment-pending banner when true.
    let isPaymentPending: Bool
    /// Max meeting length when payment is pending (default 40 min).
    let meetingTimeLimitMinutes: Int
    
    init(rawToken: String) throws {
        guard let decodedData = Data(base64Encoded: rawToken, options: .ignoreUnknownCharacters) else {
            throw NetworkError.decodingFailed("Zoom response is not valid Base64.")
        }
        
        let payload: ZoomPlatformPayload
        do {
            payload = try JSONDecoder().decode(ZoomPlatformPayload.self, from: decodedData)
        } catch {
            throw NetworkError.decodingFailed("Invalid Zoom platform payload: \(error.localizedDescription)")
        }
        
        guard let ios = payload.iOS else {
            throw NetworkError.decodingFailed("Zoom payload missing iOS parameters.")
        }
        
        // Host receives StartMeetingParamsWithoutLogin; participant receives JoinMeetingParams.
        let startMeeting = ios.startMeeting
        let joinMeeting = ios.joinMeeting
        let active = startMeeting ?? joinMeeting
        let sdkInit = ios.sdkInit
        let user = ios.userMap
        
        status = nil
        success = nil
        message = nil
        token = rawToken
        zak = active?.zoomAccessToken
        sdkToken = nil
        jwt = sdkInit?.jwtToken
        signature = nil
        sdkKey = nil
        meetingNumber = active?.meetingNo
        meetingId = nil
        password = active?.password
        passcode = nil
        userName = active?.displayName ?? user?.username
        banner = user?.banner
        userId = nil
        expiry = nil
        expiryDate = user?.expiryDate
        expiresAt = nil
        expiresInDays = user?.daysLeft
        data = nil
        role = startMeeting != nil ? .host : (joinMeeting != nil ? .participant : nil)
        if let json = try? JSONSerialization.jsonObject(with: decodedData) {
            hostJoinAvailable = HostJoinAvailability.canParticipantJoin(json: json)
            profileImageURL = HostProfileImageURL.parse(from: json)
            bookOwnerName = HostBookName.parse(from: json)
            bookName = ZoomPayloadText.find(
                in: json,
                keys: ["book name", "bookName", "book_name", "bookTitle", "book_title"]
            )
            clientMessage = ZoomPayloadText.find(
                in: json,
                keys: ["client message","client Message", "clientMessage", "client_message", "clientMsg"]
            )
            accountUsername = user?.username ?? ZoomPayloadText.find(
                in: json,
                keys: ["username", "userName"]
            )
            isPaymentPending = ZoomPaymentStatus.isPending(json: json)
            meetingTimeLimitMinutes = ZoomPaymentStatus.meetingLimitMinutes(json: json)
        } else {
            hostJoinAvailable = true
            profileImageURL = nil
            bookOwnerName = nil
            bookName = nil
            clientMessage = nil
            accountUsername = nil
            isPaymentPending = false
            meetingTimeLimitMinutes = ZoomPaymentStatus.defaultMeetingLimitMinutes
        }
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        ?? c.decodeIfPresent(String.self, forKey: .zoom_token)
        ?? c.decodeIfPresent(String.self, forKey: .access_token)
        zak = try c.decodeIfPresent(String.self, forKey: .zak)
        sdkToken = try c.decodeIfPresent(String.self, forKey: .sdkToken)
        jwt = try c.decodeIfPresent(String.self, forKey: .jwt)
        signature = try c.decodeIfPresent(String.self, forKey: .signature)
        sdkKey = try c.decodeIfPresent(String.self, forKey: .sdkKey)
        meetingNumber = try c.decodeIfPresent(String.self, forKey: .meetingNumber)
        ?? c.decodeIfPresent(String.self, forKey: .meeting_number)
        meetingId = try c.decodeIfPresent(String.self, forKey: .meetingId)
        ?? c.decodeIfPresent(String.self, forKey: .meeting_id)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        passcode = try c.decodeIfPresent(String.self, forKey: .passcode)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        expiry = try c.decodeIfPresent(String.self, forKey: .expiry)
        ?? c.decodeIfPresent(String.self, forKey: .expire_date)
        ?? c.decodeIfPresent(String.self, forKey: .expireDate)
        expiryDate = try c.decodeIfPresent(String.self, forKey: .expiryDate)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        expiresInDays = try c.decodeIfPresent(Int.self, forKey: .expiresInDays)
        data = try c.decodeIfPresent(ZoomTokenData.self, forKey: .data)
        role = nil
        hostJoinAvailable = true
        profileImageURL = nil
        bookOwnerName = nil
        bookName = nil
        banner = nil
        clientMessage = nil
        accountUsername = nil
        isPaymentPending = false
        meetingTimeLimitMinutes = ZoomPaymentStatus.defaultMeetingLimitMinutes
    }
}

enum ZoomRole: String, Sendable {
    case host
    case participant
}

private struct ZoomPlatformPayload: Decodable {
    let iOS: ZoomIOSPayload?
    
    enum CodingKeys: String, CodingKey {
        case iOS
    }
}

private struct ZoomIOSPayload: Decodable {
    let startMeeting: ZoomMeetingParamsPayload?
    let joinMeeting: ZoomMeetingParamsPayload?
    let sdkInit: ZoomSDKInitPayload?
    let userMap: ZoomUserPayload?
    
    enum CodingKeys: String, CodingKey {
        case startMeeting = "StartMeetingParamsWithoutLogin"
        case joinMeeting = "JoinMeetingParams"
        case sdkInit = "ZoomSDKInitParams"
        case userMap
    }
}

/// Shared shape for both start (host) and join (participant) parameter blocks.
/// All fields are optional and multiple key spellings are accepted so the app
/// never crashes on a shape it hasn't seen before.
private struct ZoomMeetingParamsPayload: Decodable {
    let meetingNo: String?
    let zoomAccessToken: String?
    let password: String?
    let displayName: String?
    
    enum CodingKeys: String, CodingKey {
        case meetingNo, meetingNumber
        case zoomAccessToken, zak
        case password, meetingPassword, pwd, passcode
        case displayName, userName
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingNo = Self.flexibleString(c, .meetingNo)
        ?? Self.flexibleString(c, .meetingNumber)
        zoomAccessToken = try c.decodeIfPresent(String.self, forKey: .zoomAccessToken)
        ?? c.decodeIfPresent(String.self, forKey: .zak)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        ?? c.decodeIfPresent(String.self, forKey: .meetingPassword)
        ?? c.decodeIfPresent(String.self, forKey: .pwd)
        ?? c.decodeIfPresent(String.self, forKey: .passcode)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        ?? c.decodeIfPresent(String.self, forKey: .userName)
    }
    
    /// Meeting numbers sometimes arrive as JSON numbers instead of strings.
    private static func flexibleString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? c.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? c.decode(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? c.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

private struct ZoomSDKInitPayload: Decodable {
    let jwtToken: String?
}

private struct ZoomUserPayload: Decodable {
    let expiryDate: String?
    let daysLeft: Int?
    let username: String?
    let banner: String?

    enum CodingKeys: String, CodingKey {
        case expiryDate, daysLeft, username,banner, userName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiryDate = try c.decodeIfPresent(String.self, forKey: .expiryDate)
        daysLeft = try c.decodeIfPresent(Int.self, forKey: .daysLeft)
        username = Self.flexibleString(c, .username) ?? Self.flexibleString(c, .userName)
        banner = Self.flexibleString(c, .banner) ?? Self.flexibleString(c, .banner)
    }

    /// Usernames sometimes arrive as JSON numbers (`1155`) instead of strings.
    private static func flexibleString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? c.decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? c.decode(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? c.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct ZoomTokenData: Decodable, Equatable {
    let token: String?
    let zak: String?
    let sdkToken: String?
    let jwt: String?
    let signature: String?
    let sdkKey: String?
    let meetingNumber: String?
    let meetingId: String?
    let password: String?
    let passcode: String?
    let userName: String?
    let expiry: String?
    let expiryDate: String?
    let expiresInDays: Int?
    
    enum CodingKeys: String, CodingKey {
        case token, zak, sdkToken, jwt, signature, sdkKey
        case meetingNumber, meetingId, password, passcode, userName
        case expiry, expiryDate, expiresInDays
        case meeting_number, meeting_id, zoom_token
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        ?? c.decodeIfPresent(String.self, forKey: .zoom_token)
        zak = try c.decodeIfPresent(String.self, forKey: .zak)
        sdkToken = try c.decodeIfPresent(String.self, forKey: .sdkToken)
        jwt = try c.decodeIfPresent(String.self, forKey: .jwt)
        signature = try c.decodeIfPresent(String.self, forKey: .signature)
        sdkKey = try c.decodeIfPresent(String.self, forKey: .sdkKey)
        meetingNumber = try c.decodeIfPresent(String.self, forKey: .meetingNumber)
        ?? c.decodeIfPresent(String.self, forKey: .meeting_number)
        meetingId = try c.decodeIfPresent(String.self, forKey: .meetingId)
        ?? c.decodeIfPresent(String.self, forKey: .meeting_id)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        passcode = try c.decodeIfPresent(String.self, forKey: .passcode)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
        expiry = try c.decodeIfPresent(String.self, forKey: .expiry)
        expiryDate = try c.decodeIfPresent(String.self, forKey: .expiryDate)
        expiresInDays = try c.decodeIfPresent(Int.self, forKey: .expiresInDays)
    }
}

/// Normalized credentials consumed by ZoomAudioMeetingService.
struct ZoomMeetingCredentials: Equatable, Sendable {
    let role: ZoomRole
    let jwtOrSDKToken: String
    let meetingNumber: String
    let password: String
    let displayName: String
    let zak: String?
    let sdkKey: String?
    let expiryDisplay: String?
    let expiresInDays: Int?
    /// From zoom-token payload — `false` when host has not started / number is off.
    let hostJoinAvailable: Bool
    /// Host profile from `https://telecom.ac/api/files/...` when present in userMap.
    let profileImageURL: URL?
    /// Book owner name from zoom-token `userMap` (participant card title + name pill).
    let bookOwnerName: String?
    /// `book name` field. Shown in the top pill when present.
    let bookName: String?
    let banner: String?
    /// `client message` field. Shown under the participant avatar.
    let clientMessage: String?
    /// Account username from the zoom token. Shown even when it is only digits.
    let accountUsername: String?
    /// Host-only: Zoom account payment pending (from `userMap` / platform payload).
    let isPaymentPending: Bool
    /// Host meeting cap when payment is pending (minutes).
    let meetingTimeLimitMinutes: Int
    
    var isHost: Bool { role == .host }
    
    static func from(response: ZoomTokenResponse, fallbackUsername: String) throws -> ZoomMeetingCredentials {
        let nested = response.data
        
        let token = firstNonEmpty(
            response.sdkToken,
            response.jwt,
            response.token,
            nested?.sdkToken,
            nested?.jwt,
            nested?.token,
            response.signature,
            nested?.signature
        )
        
        let meeting = firstNonEmpty(
            response.meetingNumber,
            response.meetingId,
            nested?.meetingNumber,
            nested?.meetingId
        )
        
        guard let token else {
            throw NetworkError.decodingFailed("Zoom token missing in API response. MAP_AFTER_REAL_RESPONSE in ZoomModels.swift")
        }
        guard let meeting else {
            throw NetworkError.decodingFailed("Meeting number missing in API response. MAP_AFTER_REAL_RESPONSE in ZoomModels.swift")
        }
        
        let password = firstNonEmpty(
            response.password,
            response.passcode,
            nested?.password,
            nested?.passcode
        ) ?? ""
        
        let name = Self.zoomJoinName(
            displayName: response.userName ?? nested?.userName ?? fallbackUsername,
            username: response.accountUsername
        )
        let expiry = firstNonEmpty(
            response.expiry,
            response.expiryDate,
            response.expiresAt,
            nested?.expiry,
            nested?.expiryDate
        )
        let days = response.expiresInDays ?? nested?.expiresInDays
        
        // A host receives a Zoom access token (ZAK) to start the meeting; a
        // participant does not and instead joins with the meeting number.
        let zak = response.zak ?? nested?.zak
        let role: ZoomRole
        if let responseRole = response.role {
            role = responseRole
        } else if let zak, !zak.isEmpty {
            role = .host
        } else {
            role = .participant
        }
        
        return ZoomMeetingCredentials(
            role: role,
            jwtOrSDKToken: token,
            meetingNumber: meeting,
            password: password,
            displayName: name,
            zak: zak,
            sdkKey: response.sdkKey ?? nested?.sdkKey,
            expiryDisplay: expiry,
            expiresInDays: days,
            hostJoinAvailable: response.hostJoinAvailable,
            profileImageURL: response.profileImageURL,
            bookOwnerName: response.bookOwnerName,
            bookName: response.bookName,
            banner: response.banner,
            clientMessage: response.clientMessage,
            accountUsername: response.accountUsername,
            isPaymentPending: response.isPaymentPending,
            meetingTimeLimitMinutes: response.meetingTimeLimitMinutes
        )
    }
    
    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Numeric usernames are sent as `1155::::JOHN` so the host card can show both.
    private static func zoomJoinName(displayName: String, username: String?) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              username.allSatisfy(\.isNumber),
              name != username,
              !name.hasPrefix("\(username)::::") else {
            return name
        }
        return "\(username)::::\(name)"
    }
}
/// before the participant SDK join flow starts.
enum HostJoinAvailability {
    static let unavailableMessage = "Host is not available, number is switchoff"

    static func canParticipantJoin(json: Any) -> Bool {
        guard let root = json as? [String: Any] else { return true }
        if indicatesUnavailable(root) { return false }
        if let ios = root["iOS"] as? [String: Any] {
            if indicatesUnavailable(ios) { return false }
            if let userMap = ios["userMap"] as? [String: Any], indicatesUnavailable(userMap) {
                return false
            }
        }
        return true
    }

    private static func indicatesUnavailable(_ dict: [String: Any]) -> Bool {
        for (key, value) in dict {
            let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
            if normalized.contains("switchoff")
                || normalized == "numberswitchoff"
                || normalized == "isnumberoff"
                || normalized == "numberoff" {
                if parseTruthy(value) { return true }
            }
            if normalized == "hostinmeeting"
                || normalized == "ishostinmeeting"
                || normalized == "hoststarted"
                || normalized == "meetingstarted"
                || normalized == "ismeetingstarted" {
                if parseFalsy(value) { return true }
            }
            if normalized == "hostavailable"
                || normalized == "ishostavailable"
                || normalized == "canjoin"
                || normalized == "canjoinmeeting"
                || normalized == "joinallowed" {
                if parseFalsy(value) { return true }
            }
            if normalized == "hoststatus" || normalized == "meetingstatus" || normalized == "status" {
                if let text = value as? String {
                    let lower = text.lowercased()
                    if lower.contains("switchoff")
                        || lower.contains("not available")
                        || lower.contains("offline")
                        || lower.contains("not started") {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func parseTruthy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: return bool
        case let int as Int: return int != 0
        case let double as Double: return double != 0
        case let string as String:
            let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "true" || lower == "1" || lower == "yes" || lower.contains("switchoff")
        default:
            return false
        }
    }

    private static func parseFalsy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: return !bool
        case let int as Int: return int == 0
        case let double as Double: return double == 0
        case let string as String:
            let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "false" || lower == "0" || lower == "no" || lower == "off"
        default:
            return false
        }
    }
}

/// Finds a string field anywhere in the zoom-token JSON.
/// Key match ignores spaces, underscores, and capitalization (`"book name"` == `bookName`).
enum ZoomPayloadText {
    static func find(in json: Any, keys: [String]) -> String? {
        let wanted = Set(keys.map(normalize))
        return search(json, wanted: wanted)
    }

    private static func search(_ value: Any, wanted: Set<String>) -> String? {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict where wanted.contains(normalize(key)) {
                if let text = clean(nested) { return text }
            }
            for nested in dict.values {
                if let text = search(nested, wanted: wanted) { return text }
            }
        } else if let list = value as? [Any] {
            for nested in list {
                if let text = search(nested, wanted: wanted) { return text }
            }
        }
        return nil
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().filter(\.isLetter)
    }

    private static func clean(_ value: Any) -> String? {
        let raw: String?
        if let text = value as? String {
            raw = text
        } else if let number = value as? NSNumber {
            raw = number.stringValue
        } else {
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Book / host owner name from zoom-token `userMap` (same source as profile image).
enum HostBookName {
    static func parse(from json: Any) -> String? {
        guard let root = json as? [String: Any] else { return nil }

        if let ios = root["iOS"] as? [String: Any] {
            if let userMap = ios["userMap"] as? [String: Any],
               let name = pickName(from: userMap) {
                return name
            }
            if let start = ios["StartMeetingParamsWithoutLogin"] as? [String: Any],
               let name = pickName(from: start) {
                return name
            }
        }

        return pickName(from: root)
    }

    private static func pickName(from dict: [String: Any]) -> String? {
        let prioritizedKeys = [
            "bookName", "book_name", "bookTitle", "book_title", "book",
            "username", "userName", "ownerName", "owner_name",
            "hostName", "host_name", "name", "displayName", "display_name"
        ]

        for key in prioritizedKeys {
            if let value = dict[key] as? String,
               let cleaned = sanitize(value) {
                return cleaned
            }
        }

        for (key, value) in dict {
            guard let string = value as? String else { continue }
            let normalizedKey = key.lowercased().replacingOccurrences(of: "_", with: "")
            guard normalizedKey.contains("book")
//                || normalizedKey == "username"
                || normalizedKey.contains("ownername")
                || normalizedKey.contains("hostname")
                || normalizedKey == "name"
                || normalizedKey.contains("displayname") else { continue }
            if let cleaned = sanitize(string) { return cleaned }
        }

        return nil
    }

    private static func sanitize(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name.contains("/api/files/") || name.hasPrefix("http://") || name.hasPrefix("https://") {
            return nil
        }
        while name.hasSuffix(":") {
            name.removeLast()
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.lowercased() != "host" else { return nil }
        return name
    }
}

/// Host payment / free-meeting limits from zoom-token `userMap`.
enum ZoomPaymentStatus {
    static let defaultMeetingLimitMinutes = 40

    static func isPending(json: Any) -> Bool {
        guard let root = json as? [String: Any] else { return false }
        if indicatesPending(root) { return true }
        if let ios = root["iOS"] as? [String: Any] {
            if indicatesPending(ios) { return true }
            if let userMap = ios["userMap"] as? [String: Any], indicatesPending(userMap) {
                return true
            }
        }
        return false
    }

    static func meetingLimitMinutes(json: Any) -> Int {
        guard let root = json as? [String: Any] else { return defaultMeetingLimitMinutes }
        if let minutes = parseLimitMinutes(root) { return minutes }
        if let ios = root["iOS"] as? [String: Any] {
            if let minutes = parseLimitMinutes(ios) { return minutes }
            if let userMap = ios["userMap"] as? [String: Any],
               let minutes = parseLimitMinutes(userMap) {
                return minutes
            }
        }
        return defaultMeetingLimitMinutes
    }

    private static func indicatesPending(_ dict: [String: Any]) -> Bool {
        for (key, value) in dict {
            let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
            if normalized == "paymentpending"
                || normalized == "ispaymentpending"
                || normalized == "zoompaymentpending"
                || normalized == "accountpaymentpending"
                || normalized == "paymentdue"
                || normalized == "ispaymentdue" {
                if parseTruthy(value) { return true }
            }
            if normalized == "paymentstatus"
                || normalized == "subscriptionstatus"
                || normalized == "accountstatus"
                || normalized == "billingstatus" {
                if let text = value as? String {
                    let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if lower.contains("pending")
                        || lower.contains("unpaid")
                        || lower.contains("pastdue")
                        || lower.contains("past_due")
                        || lower.contains("due") {
                        return true
                    }
                }
            }
            if normalized == "ispaid" || normalized == "paymentdone" || normalized == "haspaid" {
                if parseFalsy(value) { return true }
            }
        }
        return false
    }

    private static func parseLimitMinutes(_ dict: [String: Any]) -> Int? {
        let keys = [
            "meetingTimeLimitMinutes", "meetingtimelimitminutes",
            "meetingLimitMinutes", "meetinglimitminutes",
            "freeMeetingMinutes", "freemeetingminutes",
            "meetingDurationLimit", "meetingdurationlimit",
            "zoomMeetingLimit", "zoommeetinglimit"
        ]
        for key in keys {
            if let int = dict[key] as? Int, int > 0 { return int }
            if let string = dict[key] as? String, let int = Int(string), int > 0 { return int }
        }
        for (key, value) in dict {
            let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
            guard normalized.contains("meetinglimit")
                || normalized.contains("timelimit")
                || normalized.contains("freeminute")
                || normalized.contains("durationlimit") else { continue }
            if let int = value as? Int, int > 0 { return int }
            if let string = value as? String, let int = Int(string), int > 0 { return int }
        }
        return nil
    }

    private static func parseTruthy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: return bool
        case let int as Int: return int != 0
        case let string as String:
            let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "true" || lower == "1" || lower == "yes" || lower.contains("pending")
        default:
            return false
        }
    }

    private static func parseFalsy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: return !bool
        case let int as Int: return int == 0
        case let string as String:
            let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "false" || lower == "0" || lower == "no"
        default:
            return false
        }
    }
}
