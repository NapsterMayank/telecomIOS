//
//  AppDelegate.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//
import UIKit
import SwiftUI
import OneSignalFramework

#if canImport(MobileRTC)
import MobileRTC
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    private static let oneSignalAppID = "f6e56a6e-ce42-453d-939e-3481f68e3778"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        OneSignal.initialize(Self.oneSignalAppID, withLaunchOptions: launchOptions)
        OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
        SirenManager.shared.checkForAppUpdates()
        return true
    }

    // Zoom Meeting SDK requires these hooks for background audio. Only call
    // after SDK init — messaging MobileRTC before initialize() can EXC_BAD_ACCESS.
    func applicationWillResignActive(_ application: UIApplication) {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard ZoomSDKManager.shared.isInitialized else { return }
        MobileRTC.shared().appWillResignActive()
        #endif
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard ZoomSDKManager.shared.isInitialized else { return }
        MobileRTC.shared().appDidBecomeActive()
        #endif
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard ZoomSDKManager.shared.isInitialized else { return }
        MobileRTC.shared().appDidEnterBackground()
        #endif
    }

    func applicationWillTerminate(_ application: UIApplication) {
        #if ZOOM_MEETING_SDK && canImport(MobileRTC)
        guard ZoomSDKManager.shared.isInitialized else { return }
        MobileRTC.shared().appWillTerminate()
        #endif
    }
}
