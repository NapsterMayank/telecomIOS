//
//  ScrollingMarqueeText.swift
//  Learning
//

import SwiftUI
import UIKit

/// Continuous left-scrolling ticker (competitor-style payment warning).
struct ScrollingMarqueeText: View {
    let text: String
    var textColor: Color = AppColors.muteRed
    var font: Font = .system(size: 13, weight: .semibold)
    var speedPointsPerSecond: CGFloat = 40
    var gap: CGFloat = 48

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            GeometryReader { geo in
                let measured = textWidth(in: geo.size.height)
                let cycle = max(measured + gap, geo.size.width + gap)
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let offset = CGFloat(elapsed * Double(speedPointsPerSecond))
                    .truncatingRemainder(dividingBy: Double(cycle))

                HStack(spacing: gap) {
                    marqueeLabel
                    marqueeLabel
                }
                .offset(x: -offset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
            }
        }
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func textWidth(in height: CGFloat) -> CGFloat {
        let uiFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: uiFont])
        return ceil(size.width)
    }
}
