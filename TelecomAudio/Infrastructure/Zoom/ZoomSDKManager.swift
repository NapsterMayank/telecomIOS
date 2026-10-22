//
//  ZoomSDKManager.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import UIKit

#if canImport(MobileRTC)
import MobileRTC
#endif

/// Isolates raw Zoom Meeting SDK (MobileRTC) lifecycle.
///
/// INTEGRATION STEPS:
/// 1. Download Zoom Meeting SDK for iOS from Zoom Marketplace.
/// 2. Add `MobileRTC.xcframework` (+ required resources) to the Xcode target.
/// 3. Enable `ZOOM_MEETING_SDK` Swift flag in Build Settings → Other Swift Flags: `-DZOOM_MEETING_SDK`
/// 4. Add microphone usage description (already in Info.plist).
/// 5. Do NOT embed Zoom secrets in the app — use JWT/token from `get-zoom-token` API.
@MainActor
final class ZoomSDKManager {
static let shared = ZoomSDKManager()

    private(set) var isInitialized = false

    private init() {}

    @MainActor
    func initialize(sdkKey: String?, jwt: String) async throws {

        #if ZOOM_MEETING_SDK && canImport(MobileRTC)

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            // Without a window scene and the resource bundle, initialize()
            // returns false and Zoom presents "MobileRTC initialize failed."
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                MobileRTC.shared().setMobileRTCPresentationScene(scene)
            }

            let context = MobileRTCSDKInitContext()
            context.domain = "https://zoom.us"
            context.enableLog = true
            context.enableCustomizeMeetingUI = true
            if let resources = Bundle.main.path(forResource: "MobileRTCResources", ofType: "bundle") {
                context.bundleResPath = resources
            }

            // initialize() may run once per process. After End Meeting the SDK
            // is still alive; calling it again returns false and Zoom shows
            // "MobileRTC initialize failed."
            if !isInitialized {
                let success = MobileRTC.shared().initialize(context)
                guard success else {
                    continuation.resume(
                        throwing: NetworkError.unknown(
                            "MobileRTC initialize failed."
                        )
                    )
                    return
                }
            }

            guard let authService = MobileRTC.shared().getAuthService() else {
                continuation.resume(
                    throwing: NetworkError.unknown(
                        "MobileRTC auth service unavailable."
                    )
                )
                return
            }

            // Still authorized from the meeting that just ended. Signing in
            // again is unnecessary and a second initialize() is what shows
            // Zoom's failure card.
            if isInitialized, MobileRTC.shared().isRTCAuthorized() {
                applyCustomMeetingSettings()
                continuation.resume()
                return
            }

            // JWT authentication
            authService.jwtToken = jwt

            if let sdkKey, !sdkKey.isEmpty {
                _ = sdkKey
            }

            authService.delegate = ZoomAuthBridge.shared

            ZoomAuthBridge.shared.onResult = { [weak self] result in

                Task { @MainActor in

                    switch result {

                    case .success:

                        self?.isInitialized = true
                        self?.applyCustomMeetingSettings()

                        continuation.resume()

                    case .failure(let error):

                        continuation.resume(
                            throwing: error
                        )
                    }
                }
            }

            authService.sdkAuth()
        }

        #else

        try await Task.sleep(
            nanoseconds: 700_000_000
        )

        isInitialized = true

        _ = sdkKey
        _ = jwt

        #endif
    }
    func deinitialize() {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        MobileRTC.shared().cleanup()
        #endif
        isInitialized = false
    }

    /// Audio-only custom UI: join muted, no video, no Zoom chrome overlays.
    private func applyCustomMeetingSettings() {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard let settings = MobileRTC.shared().getMeetingSettings() else { return }
        settings.setMuteAudioWhenJoinMeeting(true)
        settings.setMuteVideoWhenJoinMeeting(true)
        settings.disableMinimizeMeeting(true)
        settings.disableGalleryView(true)
        settings.disableShowVideoPreview(whenJoinMeeting: true)
        settings.setHideMeetingInputUserInfoWindow(true)
        #endif
    }
}

#if ZOOM_MEETING_SDK && canImport(MobileRTC)
private final class ZoomAuthBridge: NSObject, MobileRTCAuthDelegate {
    static let shared = ZoomAuthBridge()
    var onResult: ((Result<Void, Error>) -> Void)?

    func onMobileRTCAuthReturn(_ returnValue: MobileRTCAuthError) {
        if returnValue == .success {
            onResult?(.success(()))
        } else {
            onResult?(.failure(NetworkError.unknown("Zoom SDK auth failed: \(returnValue)")))
        }
        onResult = nil
    }
}
#endif
