//
//  SplashView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Android-matching splash: navy full-bleed + centered mic logo with zoom-in.
struct SplashView: View {
    @StateObject var viewModel: SplashViewModel
    @State private var logoScale: CGFloat = 0.72
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            Image("logoImage")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .accessibilityLabel("TELECOM")
        }
        .task {
            withAnimation(.easeOut(duration: 0.55)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            await viewModel.start()
        }
    }
}
