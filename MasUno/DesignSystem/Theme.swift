import SwiftUI

/// Green theme tokens (SPEC §7.1), confirmed as Figma variables in D1.
/// Views use these, never raw colors. Light mode only for now.
enum Theme {
    // MARK: Colors

    /// Primary buttons, toggles, check badges. White label is 4.9:1.
    static let accent = Color(hex: 0x12815A)
    /// Secondary buttons, status chips, initials avatars, segmented track.
    static let accentSoft = Color(hex: 0xDDF1E8)
    /// Screens and sheets.
    static let background = Color(hex: 0xF5F4F7)
    /// Cards, grouped rows, popups.
    static let card = Color(hex: 0xFDFCFE)
    /// Titles and body text.
    static let ink = Color(hex: 0x1F2638)
    /// Secondary text at any size.
    static let muted = Color(hex: 0x5F5C68)
    /// Lighter secondary text — only for ≥ 18 pt, or ≥ 14 pt bold.
    static let mutedLarge = Color(hex: 0x73707B)
    /// Map pins only.
    static let pin = Color(hex: 0x2F6FE0)
    /// Cancel game, Sign out, Delete account.
    static let destructive = Color(hex: 0xC23B34)
    /// Field errors.
    static let error = Color(hex: 0xCB3D3D)
    /// Interest chips.
    static let chipSport = Color(hex: 0xDCE4F4)

    // Derived from the tokens above.

    /// Hairline border on cards and fields, and row separators.
    static let hairline = ink.opacity(0.1)
    /// Soft drop shadow under pins and floating cards.
    static let shadow = ink.opacity(0.18)
    /// Label color on `accent` and `destructive` fills.
    static let onAccent = card
    /// Scrim behind a modal dialog.
    static let scrim = ink.opacity(0.35)

    // MARK: Metrics

    enum Radius {
        /// Fields, small tiles.
        static let field: CGFloat = 14
        /// Cards and grouped rows (Figma: 16–20).
        static let card: CGFloat = 18
        /// Popups and dialogs.
        static let dialog: CGFloat = 26
    }

    /// Full-width pill button height.
    static let buttonHeight: CGFloat = 50
    /// Compact pill ("Leave", "Edit", "Change").
    static let compactButtonHeight: CGFloat = 32
    /// Round glass buttons (back, bookmark, settings).
    static let circleButtonSize: CGFloat = 44
    /// Screen side margin.
    static let gutter: CGFloat = 20
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Card surface: `card` fill, 18 pt corners, hairline border.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline))
    }
}
