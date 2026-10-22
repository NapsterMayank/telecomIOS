//
//  AppSpacing.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import CoreGraphics
import UIKit
let screenHeight = UIScreen.main.bounds.size.height
let screenWidth = UIScreen.main.bounds.size.width

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40

    static let cardCorner: CGFloat = 40
    static let fieldCorner: CGFloat = 12
    static let buttonCorner: CGFloat = 12
    static let toastCorner: CGFloat = 22
    static let statusCardCorner: CGFloat = 24

    static let horizontalInset: CGFloat = 28
    static let cardHorizontalInset: CGFloat = 28

    /// Compact login card (Android reference).
    static let loginCardWidth: CGFloat = 340
    static let loginFieldWidth: CGFloat = 240
    static let loginCardCorner: CGFloat = 28
    static let loginCardBottomInset: CGFloat = 20
}
