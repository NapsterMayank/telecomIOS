//
//  TelecomScreenLayout.swift
//  Learning
//
//  Shared login / home shell: themed header band + elevated bottom card.
//

import SwiftUI

/// Black (light) or blue (dark) header with TELECOM branding — sits above the login card on Android.
struct TelecomHeader: View {
    var logoSize: CGFloat = 200
    var bottomPadding: CGFloat = 28

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: logoSize, height: logoSize)

                Image("logoImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize * 0.7, height: logoSize * 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text("TELECOM")
                .font(AppFonts.title(30))
                .foregroundStyle(AppColors.headerText)
                .tracking(1.5)
                .padding(.top, 20)

            Text("Audio Conference Platform")
                .font(AppFonts.body(14))
                .foregroundStyle(AppColors.headerSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, bottomPadding)
    }
}

/// Full-screen layout used by Login and Home.
struct TelecomScreenLayout<Header: View, Card: View>: View {
    var headerHeightRatio: CGFloat = 0.38
    @ViewBuilder var header: () -> Header
    @ViewBuilder var card: () -> Card

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                AppColors.screenBackground
                    .ignoresSafeArea()

                AppColors.headerBackground
                    .frame(height: proxy.size.height * headerHeightRatio)
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    header()
                        .padding(.top, proxy.safeAreaInsets.top > 0 ? 8 : 24)
                    card()
                }
            }
        }
    }
}

/// Rounded card with theme-aware elevation shadow (original simple style).
struct TelecomCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: AppSpacing.loginCardWidth)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.loginCardCorner, style: .continuous)
                    .fill(AppColors.cardBackground)
            )
            .shadow(
                color: .black.opacity(AppColors.cardShadowOpacity(for: colorScheme)),
                radius: colorScheme == .dark ? 16 : 15,
                x: 0,
                y: 6
            )
    }
}

/// Applies themed screen background to navigation-based screens.
struct TelecomScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.screenBackground.ignoresSafeArea())
    }
}

extension View {
    func telecomScreenBackground() -> some View {
        modifier(TelecomScreenBackground())
    }
}
