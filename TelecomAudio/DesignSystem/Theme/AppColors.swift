//
//  AppColors.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI
import UIKit

/// Visual tokens mirrored from the Android TELECOM screenshots, with light/dark
/// variants for auth and dashboard screens.
enum AppColors {
    static let black = Color.black
    static let white = Color.white

    /// Brand accent — dark-theme header + primary button (`#56CCF2`).
    static let accentBlue = Color(red: 86 / 255, green: 204 / 255, blue: 242 / 255)

    // MARK: - Theme-aware (light / dark)

    static let screenBackground = dynamic(
        light: UIColor(red: 248 / 255, green: 248 / 255, blue: 248 / 255, alpha: 1),
        dark: UIColor(red: 14 / 255, green: 14 / 255, blue: 16 / 255, alpha: 1)
    )

    /// Top header band on login / home.
    static let headerBackground = dynamic(
        light: .black,
        dark: UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
    )

    static let headerText = dynamic(
        light: .white,
        dark: UIColor(red: 13 / 255, green: 27 / 255, blue: 62 / 255, alpha: 1)
    )

    static let headerSubtitle = dynamic(
        light: UIColor(white: 1, alpha: 0.9),
        dark: UIColor(red: 13 / 255, green: 27 / 255, blue: 62 / 255, alpha: 0.85)
    )

    static let cardBackground = dynamic(
        light: .white,
        dark: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
    )

    static let textPrimary = dynamic(
        light: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1),
        dark: UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
    )

    static let textSecondary = dynamic(
        light: UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1),
        dark: UIColor(red: 152 / 255, green: 152 / 255, blue: 157 / 255, alpha: 1)
    )

    static let textMuted = dynamic(
        light: UIColor(red: 160 / 255, green: 160 / 255, blue: 160 / 255, alpha: 1),
        dark: UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 1)
    )

    static let border = dynamic(
        light: UIColor(red: 220 / 255, green: 220 / 255, blue: 220 / 255, alpha: 1),
        dark: UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )

    static let fieldBackground = dynamic(
        light: .white,
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )

    static let fieldBorder = dynamic(
        light: UIColor(red: 210 / 255, green: 210 / 255, blue: 210 / 255, alpha: 1),
        dark: UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )

    /// UIKit brand tint — black (light), cyan (dark). For UIKit surfaces such as alerts.
    static let brandTintUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
            : .black
    }

    static let primaryButtonBackground = Color(brandTintUIColor)

    /// Login / Start Meeting label — white on black (light), black on cyan (dark).
    static let primaryButtonForeground = dynamic(
        light: .white,
        dark: UIColor(red: 13 / 255, green: 27 / 255, blue: 62 / 255, alpha: 1)
    )

    /// Focused text-field stroke — black (light), cyan (dark).
    static let fieldFocusBorder = dynamic(
        light: .black,
        dark: UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
    )

    /// Reset-password lock + Submit accent.
    static let modalAccent = dynamic(
        light: .black,
        dark: UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
    )

    static let secondaryButtonBackground = dynamic(
        light: .white,
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )

    static let meetingBackground = dynamic(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 18 / 255, green: 18 / 255, blue: 20 / 255, alpha: 1)
    )

    /// Legacy alias — prefer `screenBackground`.
    static let backgroundLight = screenBackground

    // MARK: - Meeting / brand (fixed)

    /// Meeting chrome / top & bottom bars (`#0D1B3E` approx from Android).
    static let navy = Color(red: 13 / 255, green: 27 / 255, blue: 62 / 255)

    /// Logo circle fill.
    static let logoNavy = Color(red: 0 / 255, green: 26 / 255, blue: 51 / 255)

    static let logoutRed = Color(red: 198 / 255, green: 40 / 255, blue: 40 / 255)
    static let logoutBorder = Color(red: 239 / 255, green: 154 / 255, blue: 154 / 255)
    static let endRed = Color(red: 255 / 255, green: 0 / 255, blue: 0 / 255)

    static let speakerGreen = Color(red: 76 / 255, green: 175 / 255, blue: 80 / 255)
    static let muteRed = Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255)

    /// Host participant card — joining / handsfree (Android yellow).
    static let participantCardYellow = Color(red: 255 / 255, green: 193 / 255, blue: 7 / 255)
    /// Host participant card — listening on speaker (Android bright lime).
    static let participantCardGreen = Color(red: 148 / 255, green: 215 / 255, blue: 104 / 255)
    /// Host participant card — participant paused / Unlisten (purple).
    static let participantCardPurple = Color(red: 156 / 255, green: 109 / 255, blue: 201 / 255)
    /// Legacy alias — same as purple pause card.
    static let participantCardOrange = participantCardPurple
    /// Host participant card — actively speaking (Android #ED736E).
    static let participantCardSpeaking = Color(red: 237 / 255, green: 115 / 255, blue: 110 / 255)
    /// Host/co-host duplicate session card — idle (Android light cyan).
    static let participantCardCohostIdle = Color(red: 178 / 255, green: 235 / 255, blue: 242 / 255)
    /// Host/co-host duplicate session — voice activity (Android cyan).
    static let participantCardHostCohostSpeaking = accentBlue

    /// Expiry strip — light mint / dark forest (Android), not red.
    static let expiryBackground = dynamic(
        light: UIColor(red: 200 / 255, green: 230 / 255, blue: 201 / 255, alpha: 1),
        dark: UIColor(red: 27 / 255, green: 48 / 255, blue: 34 / 255, alpha: 1)
    )
    static let expiryText = dynamic(
        light: UIColor(red: 46 / 255, green: 125 / 255, blue: 50 / 255, alpha: 1),
        dark: UIColor(red: 129 / 255, green: 199 / 255, blue: 132 / 255, alpha: 1)
    )
    static let expiryDivider = dynamic(
        light: UIColor(red: 76 / 255, green: 175 / 255, blue: 80 / 255, alpha: 0.45),
        dark: UIColor(red: 124 / 255, green: 252 / 255, blue: 0 / 255, alpha: 0.85)
    )

    static let progressInactive = dynamic(
        light: UIColor(red: 217 / 255, green: 217 / 255, blue: 217 / 255, alpha: 1),
        dark: UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )

    static let sideTab = Color(red: 200 / 255, green: 200 / 255, blue: 200 / 255)

    /// "Pause" action button on the local recording session screen.
    static let pauseWine = Color(red: 123 / 255, green: 32 / 255, blue: 57 / 255)

    /// "Speaker"/"Recordings" action buttons on the local recording session screen.
    static let controlSlate = Color(red: 92 / 255, green: 96 / 255, blue: 120 / 255)

    /// Username pill background on the local recording session screen.
    static let namePillLavender = Color(red: 229 / 255, green: 224 / 255, blue: 245 / 255)

    /// Cloud Recordings list card — lavender in light, muted purple-gray in dark.
    static let cloudRecordingCard = dynamic(
        light: UIColor(red: 229 / 255, green: 224 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 42 / 255, green: 44 / 255, blue: 48 / 255, alpha: 1)
    )

    /// Calendar / clock / play / share icons on cloud cards.
    static let cloudMetaIcon = dynamic(
        light: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1),
        dark: UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
    )

    /// Duration pill behind “0:02 Hrs”.
    static let cloudDurationBadge = dynamic(
        light: UIColor(red: 209 / 255, green: 209 / 255, blue: 214 / 255, alpha: 1),
        dark: UIColor(red: 28 / 255, green: 30 / 255, blue: 34 / 255, alpha: 1)
    )

    static let cloudDurationText = dynamic(
        light: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1),
        dark: UIColor(red: 86 / 255, green: 204 / 255, blue: 242 / 255, alpha: 1)
    )

    /// "Recording..." status pill background (Android gray).
    static let recordingPill = Color(red: 97 / 255, green: 97 / 255, blue: 97 / 255)
    /// "Stopped" status pill background.
    static let recordingStoppedPill = Color(red: 66 / 255, green: 66 / 255, blue: 66 / 255)
    /// "Stopping in Xs" status pill background.
    static let recordingStoppingPill = Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)

    /// Glow rings behind the big mic toggle when unmuted.
    static let micGlowGreen = Color(red: 76 / 255, green: 175 / 255, blue: 80 / 255)

    /// Participant big-mic idle gray + Listen All Resume button gray.
    static let participantMicGray = Color(red: 110 / 255, green: 110 / 255, blue: 110 / 255)

    // MARK: - Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static func cardShadowOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.35 : 0.15
    }

    static func fieldShadowOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0 : 0.08
    }
}
