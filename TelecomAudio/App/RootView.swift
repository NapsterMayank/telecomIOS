//
//  RootView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var container: AppDependencyContainer
    @ObservedObject private var appUpdate = SirenManager.shared
    
    private var isHomeOverlayPresented: Bool {
        router.isResetPasswordPresented
        || router.isCloudRecordingsPresented
        || router.isLocalRecordingsListPresented
    }
    
    var body: some View {
        Group {
            switch router.state {
            case .splash:
                SplashView(
                    viewModel: SplashViewModel(
                        sessionManager: container.sessionManager,
                        router: router
                    )
                )
            case .login:
                LoginView(
                    viewModel: LoginViewModel(
                        authRepository: container.authRepository,
                        router: router
                    )
                )
            case .home:
                ZStack {
                    HomeView(
                        viewModel: HomeViewModel(
                            sessionManager: container.sessionManager,
                            authRepository: container.authRepository,
                            zoomRepository: container.zoomRepository,
                            meetingService: container.meetingService,
                            router: router
                        )
                    )
                    .id("home-root")
                    .allowsHitTesting(!isHomeOverlayPresented)
                    
                    if router.isResetPasswordPresented {
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()
                            .transition(.opacity)
                        
                        ResetPasswordView(
                            viewModel: ResetPasswordViewModel(
                                service: container.resetPasswordService,
                                router: router
                            )
                        )
                        .transition(.opacity)
                    }
                    
                    if router.isCloudRecordingsPresented {
                        CloudRecordingsView(
                            viewModel: CloudRecordingsViewModel(
                                repository: container.recordingsRepository,
                                router: router
                            )
                        )
                        .transition(.opacity)
                        .zIndex(10)
                    }
                    
                    if router.isLocalRecordingsListPresented {
                        LocalRecordingsListView(
                            viewModel: LocalRecordingsListViewModel(
                                router: router
                            )
                        )
                        .transition(.opacity)
                        .zIndex(10)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: router.isResetPasswordPresented)
                .animation(.easeInOut(duration: 0.2), value: router.isCloudRecordingsPresented)
                .animation(.easeInOut(duration: 0.2), value: router.isLocalRecordingsListPresented)
            case .zoomInitialization:
                if let credentials = router.meetingCredentials {
                    ZoomInitializationView(
                        viewModel: ZoomInitializationViewModel(
                            credentials: credentials,
                            meetingService: container.meetingService,
                            authRepository: container.authRepository,
                            router: router
                        )
                    )
                } else {
                    HomeView(
                        viewModel: HomeViewModel(
                            sessionManager: container.sessionManager,
                            authRepository: container.authRepository,
                            zoomRepository: container.zoomRepository,
                            meetingService: container.meetingService,
                            router: router
                        )
                    )
                }
            case .meeting:
                MeetingView(
                    viewModel: MeetingViewModel(
                        credentials: router.meetingCredentials,
                        meetingService: container.meetingService,
                        router: router,
                        recordingsRepository: container.recordingsRepository
                    )
                )
            case .recordings:
                // Fallback — prefer overlay on Home via `isCloudRecordingsPresented`.
                CloudRecordingsView(
                    viewModel: CloudRecordingsViewModel(
                        repository: container.recordingsRepository,
                        router: router
                    )
                )
            case .localRecordings:
                LocalRecordingsView(
                    viewModel: LocalRecordingsViewModel(
                        credentials: router.meetingCredentials,
                        meetingService: container.meetingService,
                        authRepository: container.authRepository,
                        sessionManager: container.sessionManager,
                        deviceInfo: container.deviceInfo,
                        router: router
                    )
                )
            case .localRecordingsList:
                LocalRecordingsListView(
                    viewModel: LocalRecordingsListViewModel(
                        router: router
                    )
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = router.toastMessage {
                TelecomToastBanner(text: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.toastMessage)
        .overlay {
            if case .login = router.state, let version = appUpdate.availableVersion {
                AppUpdateDialog(
                    version: version,
                    onUpdate: appUpdate.updateNow,
                    onNextTime: appUpdate.remindNextTime
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appUpdate.availableVersion)
        .onChange(of: router.toastMessage) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if router.toastMessage == message {
                    router.toastMessage = nil
                }
            }
        }
    }
}
