//
//  ZoomInitializationView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Android Zoom connect screen — centered card, light + dark.
struct ZoomInitializationView: View {
    @StateObject var viewModel: ZoomInitializationViewModel

    var body: some View {
        ZoomMeetingStatusScreen(
            kind: .connecting,
            title: viewModel.phase.title,
            subtitle: viewModel.phase.subtitle,
            toast: viewModel.phase.toast,
            progress: viewModel.phase.progress,
            onRetry: { viewModel.retry() },
            onCancel: { viewModel.cancel() },
            showsFailureButtons: {
                if case .failed = viewModel.phase { return true }
                return false
            }()
        )
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
        .task { await viewModel.start() }
    }
}
