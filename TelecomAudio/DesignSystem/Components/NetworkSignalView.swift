//
//  NetworkSignalView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Four-bar network signal glyph colored by `NetworkQuality`. Shared by the
/// participant session card and the host's per-participant grid cards.
struct NetworkSignalView: View {
    let quality: NetworkQuality
    /// When true (white card), unlit bars use gray so they stay visible.
    var onLightBackground: Bool = false

    private var litBars: Int {
        switch quality {
        case .unknown: return 0
        case .poor: return 1
        case .medium: return 3
        case .good: return 4
        }
    }

    private var color: Color {
        switch quality {
        case .unknown: return onLightBackground ? AppColors.textMuted : .white.opacity(0.4)
        case .poor: return AppColors.muteRed
        case .medium: return .yellow
        case .good: return AppColors.speakerGreen
        }
    }

    private var unlit: Color {
        onLightBackground ? Color.black.opacity(0.15) : Color.white.opacity(0.25)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < litBars ? color : unlit)
                    .frame(width: 3, height: 6 + CGFloat(index) * 3)
            }
        }
        .frame(height: 15, alignment: .bottom)
    }
}
