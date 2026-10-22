//
//  AppLogoView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI
import UIKit

/// Microphone + wave logo matching Android TELECOM branding.
struct AppLogoView: View {
    var size: CGFloat = 88

    var body: some View {
        Image("logoImage")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .accessibilityLabel("TELECOM")
    }
}

/// Participant session card image priority:
/// 1) API profile (`/api/files/...` from userMap) — large frame
/// 2) Zoom host avatar (local file path) — large frame
/// 3) App logo — small fallback (original size)
struct SessionAvatarView: View {
    var profileImage: UIImage?
    var zoomAvatarFileURL: URL?
    /// Profile / book image area when a remote image exists.
    var size: CGFloat = 88
    /// TELECOM logo when no host image is available.
    var logoFallbackSize: CGFloat = 88

    var body: some View {
        if let profileImage {
            remoteImage(Image(uiImage: profileImage))
        } else if let zoomAvatarFileURL,
                  let uiImage = UIImage(contentsOfFile: zoomAvatarFileURL.path) {
            remoteImage(Image(uiImage: uiImage))
        } else {
            AppLogoView(size: logoFallbackSize)
        }
    }

    private func remoteImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
            .clipped()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AppLogoView()
    }
}
