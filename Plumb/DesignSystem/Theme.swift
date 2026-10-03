//
//  Theme.swift
//  Plumb
//
//  Design tokens from tokens.json and the Design system board.
//  Every colour is dynamic: dark is the instrument theme, light is the utility theme.
//

import SwiftUI
import UIKit

// MARK: - Colour helpers

extension Color {
    /// `Color(hex: 0x52F2B8)` or `Color(hex: 0x52F2B8, opacity: 0.4)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A colour that resolves per appearance.
    init(dark: UInt32, light: UInt32, darkOpacity: Double = 1, lightOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle != .light
            let hex = isDark ? dark : light
            let alpha = isDark ? darkOpacity : lightOpacity
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

// MARK: - Tokens

/// Namespace for design tokens. Use `PM.Colors.*`, `PM.Radius.*` and friends.
enum PM {

    enum Colors {
        // Grounds
        static let background     = Color(dark: 0x0B0D0F, light: 0xF4F5F2)
        static let surface        = Color(dark: 0x15191D, light: 0xFFFFFF)
        static let surfaceSunken  = Color(dark: 0x121619, light: 0xFFFFFF)
        static let surfaceRaised  = Color(dark: 0x1B2227, light: 0xFFFFFF)
        static let iconWell       = Color(dark: 0x1E252A, light: 0xE6F2EC)

        // Lines
        static let border         = Color(dark: 0x242A30, light: 0xE2E5E1)
        static let borderStrong   = Color(dark: 0x2A3238, light: 0xD5DAD6)
        /// Tab bar top rule and list separators.
        static let divider        = Color(dark: 0x1F252A, light: 0xE2E5E1)
        /// Instrument rings and crosshairs.
        static let dialLine       = Color(dark: 0x262E34, light: 0xD2D8D3)
        static let dialRim        = Color(dark: 0x2E363C, light: 0xC3CAC5)
        static let tickMajor      = Color(dark: 0x6E7A81, light: 0x3A4247)
        static let tickMinor      = Color(dark: 0x3A444B, light: 0x9AA39E)
        /// Outline of PRO badges and dashed "new" tiles.
        static let badgeOutline   = Color(dark: 0x3A444B, light: 0xC9CFCB)

        // Text
        static let textPrimary    = Color(dark: 0xF1F4F3, light: 0x0E1113)
        static let textSecondary  = Color(dark: 0xA7B0B5, light: 0x545D63)
        static let textTertiary   = Color(dark: 0x7F8A90, light: 0x6E777D)

        // Accent
        static let accent         = Color(dark: 0x52F2B8, light: 0x007A55)
        static let accentPressed  = Color(dark: 0x8AF7CF, light: 0x005C40)
        static let accentDeep     = Color(dark: 0x1C8C66, light: 0x007A55)
        static let onAccent       = Color(dark: 0x03140D, light: 0xFFFFFF)
        static let freeBadgeFill  = Color(dark: 0x173028, light: 0xE6F2EC)
        static let recommendedFill   = Color(dark: 0x121A18, light: 0xE6F2EC)
        static let recommendedBorder = Color(dark: 0x1F3A31, light: 0xC3CAC5)

        // Segmented control thumb
        /// Segmented control track. Light mode uses a grey track so the white thumb reads.
        static let segmentTrack   = Color(dark: 0x15191D, light: 0xE8EBE7)
        static let thumb          = Color(dark: 0xF1F4F3, light: 0xFFFFFF)
        static let onThumb        = Color(dark: 0x0B0D0F, light: 0x0E1113)

        // Semantic states (never colour alone: always icon + word)
        static let neutral        = Color(dark: 0xA7B0B5, light: 0x545D63)
        static let calibrating    = Color(dark: 0xA9B6FF, light: 0x3F4FB0)
        static let measuring      = Color(dark: 0x4CC3F5, light: 0x0A6FB0)
        static let aligned        = accent
        static let warning        = Color(dark: 0xFFB547, light: 0x8A4B00)
        static let warningFill    = Color(dark: 0x2A2115, light: 0xFFF2DC)
        static let unavailable    = Color(dark: 0x6E777D, light: 0x9AA39E)

        // Report (always light paper)
        static let reportInk       = Color(hex: 0x0E1113)
        static let reportSecondary = Color(hex: 0x4F585E)
        static let reportRule      = Color(hex: 0x007A55)
        static let reportTableLine = Color(hex: 0xDDE2E0)

        /// Dial face gradient stops (classic level, compass, gauges).
        static let dialFaceTop    = Color(dark: 0x1D252A, light: 0xFFFFFF)
        static let dialFaceBottom = Color(dark: 0x0E1215, light: 0xECEFEA)
    }

    enum Radius {
        static let phone: CGFloat = 44
        static let hero: CGFloat = 28
        static let card: CGFloat = 22
        static let cardSmall: CGFloat = 18
        static let iconWell: CGFloat = 12
    }

    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        /// Screen gutter.
        static let gutter: CGFloat = 20
    }

    /// The boards are drawn on a 390 x 844 frame with a 47 pt status bar and 34 pt home indicator.
    /// Subtract these from board y values when laying out inside the safe area.
    enum Board {
        static let width: CGFloat = 390
        static let height: CGFloat = 844
        static let statusBar: CGFloat = 47
        static let homeIndicator: CGFloat = 34
    }

    enum Level {
        static let perfect: Double = 0.3
        static let nearly: Double = 1.0
    }

    enum Motion {
        static let bubbleSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let levelSnap = Animation.easeOut(duration: 0.18)
        static let cardPress = Animation.easeOut(duration: 0.12)
        static let normal = Animation.easeInOut(duration: 0.3)
        /// cubic-bezier(.2,.8,.2,1)
        static func spatial(_ duration: Double = 0.7) -> Animation {
            .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
        }
    }
}

// MARK: - Typography

extension Font {
    /// SF Pro at an exact point size. Numbers should add `.monospacedDigit()`.
    static func pm(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// SF Mono.
    static func pmMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let pmReadoutXL   = Font.system(size: 80, weight: .ultraLight)
    static let pmReadout     = Font.system(size: 56, weight: .light)
    static let pmReadoutCard = Font.system(size: 44, weight: .light)
    static let pmTitle       = Font.system(size: 30, weight: .bold)
    static let pmHeadline    = Font.system(size: 20, weight: .bold)
    static let pmNavTitle    = Font.system(size: 17, weight: .semibold)
    static let pmBody        = Font.system(size: 15, weight: .regular)
    static let pmCaption     = Font.system(size: 12, weight: .bold)
    static let pmMonoBody    = Font.system(size: 13, weight: .regular, design: .monospaced)
}

extension Font.Weight {
    /// CSS 800.
    static let extraBold: Font.Weight = .heavy
}

extension View {
    /// Title 30 / Bold / -0.6 tracking.
    func pmTitleStyle() -> some View {
        font(.pmTitle).tracking(-0.6).foregroundStyle(PM.Colors.textPrimary)
    }

    /// Headline 20 / Bold / -0.3 tracking.
    func pmHeadlineStyle() -> some View {
        font(.pmHeadline).tracking(-0.3).foregroundStyle(PM.Colors.textPrimary)
    }

    /// Uppercase caption: 12 / Bold / tracking 1.2, secondary.
    func pmCaptionStyle(tracking: CGFloat = 1.2, color: Color = PM.Colors.textSecondary) -> some View {
        font(.pmCaption).tracking(tracking).foregroundStyle(color)
    }
}
