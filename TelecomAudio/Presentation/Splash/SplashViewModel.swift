//
//  SplashViewModel.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SplashViewModel: ObservableObject {
    @Published var isReady = false

    private let sessionManager: SessionManaging
    private let router: AppRouter

    init(sessionManager: SessionManaging, router: AppRouter) {
        self.sessionManager = sessionManager
        self.router = router
    }

    func start() async {
        // Brief hold after zoom-in so splash matches Android timing (~1s total).
        try? await Task.sleep(nanoseconds: 700_000_000)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if sessionManager.isLoggedIn {
                router.showHome()
            } else {
                router.showLogin()
            }
        }
        isReady = true
    }
}
