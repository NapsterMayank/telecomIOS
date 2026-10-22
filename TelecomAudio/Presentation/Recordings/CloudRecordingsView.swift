//
//  CloudRecordingsView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI
import UIKit

/// Full-screen Cloud Recordings — Android modal layout (lavender cards + Close).
struct CloudRecordingsView: View {
    @StateObject var viewModel: CloudRecordingsViewModel
    @State private var shareItem: CloudSharePayload?

    var body: some View {
        CloudRecordingsPanel(
            state: viewModel.state,
            onClose: { viewModel.back() },
            onRetry: { Task { await viewModel.load() } },
            onPlay: { item in
                if let url = item.openURL {
                    UIApplication.shared.open(url)
                }
            },
            onShare: { item in
                shareItem = CloudSharePayload(text: item.shareMessage)
            }
        )
        .task { await viewModel.load() }
        .sheet(item: $shareItem) { payload in
            CloudActivityView(activityItems: [payload.text])
        }
    }
}
