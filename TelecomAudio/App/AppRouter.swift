//
//  AppRouter.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import SwiftUI
import Combine

enum AppState: Equatable {
    case splash
    case login
    case home
    case zoomInitialization
    case meeting
    case recordings
    case localRecordings
    case localRecordingsList
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var state: AppState = .splash
    @Published var meetingCredentials: ZoomMeetingCredentials?
    @Published var toastMessage: String?
    /// Overlays on Home — do not change `state`, so Home stays visible at the sides.
    @Published var isResetPasswordPresented = false
    @Published var isCloudRecordingsPresented = false
    @Published var isLocalRecordingsListPresented = false

    func showLogin() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state = .login
            meetingCredentials = nil
            clearHomeOverlays()
        }
    }

    func showHome() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state = .home
            clearHomeOverlays()
        }
    }

    func startMeetingFlow(credentials: ZoomMeetingCredentials) {
        meetingCredentials = credentials
        clearHomeOverlays()
        state = .zoomInitialization
    }

    func showMeeting() {
        state = .meeting
    }

    func showCloudRecordings() {
        isCloudRecordingsPresented = true
    }

    func dismissCloudRecordings() {
        isCloudRecordingsPresented = false
    }

    func showLocalRecordings() {
        state = .localRecordings
    }

    func showLocalRecordingsList() {
        isLocalRecordingsListPresented = true
    }

    func dismissLocalRecordingsList() {
        isLocalRecordingsListPresented = false
    }

    func showResetPassword() {
        isResetPasswordPresented = true
    }

    func dismissResetPassword() {
        isResetPasswordPresented = false
    }

    func presentToast(_ message: String) {
        toastMessage = message
    }

    private func clearHomeOverlays() {
        isResetPasswordPresented = false
        isCloudRecordingsPresented = false
        isLocalRecordingsListPresented = false
    }
}
