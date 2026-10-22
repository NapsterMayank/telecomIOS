//
//  TelecomApp.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI
import Combine

@main
struct LearningApp: App {
    @StateObject private var container = AppDependencyContainer()
    @StateObject private var router = AppRouter()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(router)
        }
    }
}
