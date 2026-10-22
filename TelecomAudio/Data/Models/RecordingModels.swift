//
//  CloudRecordingItem.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

/// Live API: `GET /api/zooms/sub_host/recordings`
/// `{ success, message: "RECORDINGS_FOR_SUB_HOST", data: [...] }`
struct CloudRecordingsResponse: Decodable, Equatable {
    let success: Bool?
    let message: String?
    let data: [CloudRecordingItem]?
}

struct CloudRecordingItem: Decodable, Equatable, Identifiable {
    let id: String
    let topic: String?
    let startTime: String?
    let duration: Int?
    let totalSize: Int64?
    let recordingStart: String?
    let recordingEnd: String?
    let status: String?
    let shareUrlWithPassword: String?

    enum CodingKeys: String, CodingKey {
        case topic, duration, status
        case startTime, start_time
        case totalSize, total_size
        case recordingStart, recording_start
        case recordingEnd, recording_end
        case shareUrlWithPassword, share_url_with_password
        // Legacy fallbacks
        case id, uuid
        case shareUrl, share_url
        case playUrl, play_url
        case downloadUrl, download_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
            ?? c.decodeIfPresent(String.self, forKey: .start_time)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        totalSize = try c.decodeIfPresent(Int64.self, forKey: .totalSize)
            ?? c.decodeIfPresent(Int64.self, forKey: .total_size)
        recordingStart = try c.decodeIfPresent(String.self, forKey: .recordingStart)
            ?? c.decodeIfPresent(String.self, forKey: .recording_start)
        recordingEnd = try c.decodeIfPresent(String.self, forKey: .recordingEnd)
            ?? c.decodeIfPresent(String.self, forKey: .recording_end)
        status = try c.decodeIfPresent(String.self, forKey: .status)

        let shareWithPwd = try c.decodeIfPresent(String.self, forKey: .shareUrlWithPassword)
            ?? c.decodeIfPresent(String.self, forKey: .share_url_with_password)
        let legacyShare = try c.decodeIfPresent(String.self, forKey: .shareUrl)
            ?? c.decodeIfPresent(String.self, forKey: .share_url)
        let legacyPlay = try c.decodeIfPresent(String.self, forKey: .playUrl)
            ?? c.decodeIfPresent(String.self, forKey: .play_url)
        let legacyDownload = try c.decodeIfPresent(String.self, forKey: .downloadUrl)
            ?? c.decodeIfPresent(String.self, forKey: .download_url)

        shareUrlWithPassword = shareWithPwd ?? legacyShare ?? legacyPlay ?? legacyDownload

        if let stringId = try c.decodeIfPresent(String.self, forKey: .id) {
            id = stringId
        } else if let uuid = try c.decodeIfPresent(String.self, forKey: .uuid) {
            id = uuid
        } else if let start = startTime, !start.isEmpty {
            id = start
        } else if let url = shareUrlWithPassword, !url.isEmpty {
            id = url
        } else {
            id = UUID().uuidString
        }
    }

    /// Play + share both use the Zoom link with embedded password.
    var openURL: URL? {
        url(from: shareUrlWithPassword)
    }

    var shareURL: URL? {
        url(from: shareUrlWithPassword)
    }

    /// Android share sheet text (Telecom cloud recording block).
    var shareMessage: String {
        let start = formattedShareDate(from: recordingStart ?? startTime) ?? "—"
        let end = formattedShareDate(from: recordingEnd) ?? "—"
        let mins = duration ?? 0
        let playLink = shareUrlWithPassword ?? openURL?.absoluteString ?? "—"

        return """
☁️ TELECOM CLOUD RECORDING -

* START TIME : \(start)
* END TIME : \(end)
* DURATION : \(mins) Minutes

▶️ PLAY : \(playLink)
"""
    }

    var displayTitle: String {
        let trimmed = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Recording" : trimmed
    }

    /// Android-style date: `16 Aug 2026`
    var displayDate: String {
        guard let date = parsedDate(from: startTime) else { return startTime ?? "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    /// Android-style duration: `7:14 Hrs` from minutes.
    var displayDuration: String {
        guard let minutes = duration, minutes > 0 else { return "0:00 Hrs" }
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%d:%02d Hrs", hours, mins)
    }

    /// Android-style range from `recordingStart` → `recordingEnd`.
    var displayTimeRange: String {
        guard let start = parsedDate(from: recordingStart ?? startTime) else { return "—" }
        let end = parsedDate(from: recordingEnd)
            ?? start.addingTimeInterval(TimeInterval((duration ?? 0) * 60))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "hh:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
    }

    private func url(from raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw) else { return nil }
        return url
    }

    /// Android share format: `14/08/2026 6:24 pm`
    private func formattedShareDate(from raw: String?) -> String? {
        guard let date = parsedDate(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: date)
    }

    private func parsedDate(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let fallbacks = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "dd MMM yyyy HH:mm",
            "dd/MM/yyyy HH:mm"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in fallbacks {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

struct ResetPasswordRequest: Codable, Equatable {
    let password: String
}

/// MAP_ENDPOINT / MAP_AFTER_REAL_RESPONSE for reset-password.
struct ResetPasswordResponse: Codable, Equatable {
    let status: String?
    let success: Bool?
    let message: String?
}
