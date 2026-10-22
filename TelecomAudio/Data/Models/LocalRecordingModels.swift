//
//  LocalRecordingFile.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation

/// A single locally captured audio recording, shown in the Local Recordings sheet.
/// Backed by a real `.m4a` file written by `LocalRecordingRecorder` under
/// `Documents/Recordings/` (see that type for why files — not raw Zoom SDK
/// access — is the closest supported local-recording solution).
struct LocalRecordingFile: Identifiable, Equatable {
    let id: String
    let fileName: String
    let dateGroup: String
    let sizeText: String
    let createdAt: Date
    let url: URL
    
    /// Groups a flat recordings list by date (newest date first, newest file first
    /// within each date) — shared by both the host and participant Recordings sheets.
    static func grouped(from recordings: [LocalRecordingFile]) -> [(dateGroup: String, files: [LocalRecordingFile])] {
        let groups = Dictionary(grouping: recordings, by: \.dateGroup)
        return groups
            .sorted { $0.key > $1.key }
            .map { (dateGroup: $0.key, files: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }
    
    /// Preview/test-only sample data — not used by the real recordings sheet.
    static func mockSeed(referenceDate: Date = Date()) -> [LocalRecordingFile] {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dateGroup = dayFormatter.string(from: referenceDate)
        let tempDir = FileManager.default.temporaryDirectory
        
        let entries: [(offsetSeconds: Double, label: String, sizeKB: Int)] = [
//            (0, "REC__21st_Jul_09:59:40_PM", 165),
//            (38, "REC__21st_Jul_09:59:02_PM", 196),
//            (67, "REC__21st_Jul_09:58:33_PM", 262),
//            (179, "REC__21st_Jul_09:56:41_PM", 170),
//            (330, "REC__21st_Jul_09:54:10_PM", 161),
//            (383, "REC__21st_Jul_09:53:17_PM", 215),
//            (390, "REC__21st_Jul_09:53:10_PM", 145),
//            (519, "REC__21st_Jul_09:51:23_PM", 171),
//            (561, "REC__21st_Jul_09:51:01_PM", 157)
        ]
        
        return entries.map { entry in
            LocalRecordingFile(
                id: entry.label,
                fileName: entry.label,
                dateGroup: dateGroup,
                sizeText: "\(entry.sizeKB) KB",
                createdAt: referenceDate.addingTimeInterval(-entry.offsetSeconds),
                url: tempDir.appendingPathComponent(entry.label).appendingPathExtension("m4a")
            )
        }
    }
}
