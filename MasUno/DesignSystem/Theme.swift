import SwiftUI

/// Green theme tokens (SPEC §7.1). The colors live in `Assets.xcassets` (Colors/ and
/// AccentColor) as named color sets, so they match the Figma variables one-to-one and can
/// get dark variants later. Views use these, never raw colors. Light mode only for now.
enum Theme {
    // MARK: Colors

    /// Primary buttons, toggles, check badges. White label is 4.9:1.
    static let accent = Color(.accent)
    /// Secondary buttons, status chips, initials avatars, segmented track.
    static let accentSoft = Color(.accentSoft)
    /// Screens and sheets.
    static let background = Color(.background)
    /// Cards, grouped rows, popups.
    static let card = Color(.card)
    /// Titles and body text.
    static let ink = Color(.ink)
    /// Secondary text at any size.
    static let muted = Color(.muted)
    /// Lighter secondary text — only for ≥ 18 pt, or ≥ 14 pt bold.
    static let mutedLarge = Color(.mutedLarge)
    /// Map pins only.
    static let pin = Color(.pin)
    /// Cancel game, Sign out, Delete account.
    static let destructive = Color(.destructive)
    /// Field errors.
    static let error = Color(.error)
    /// Interest chips.
    static let chipSport = Color(.chipSport)

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

extension View {
    /// Card surface: `card` fill, 18 pt corners, hairline border.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline))
    }
}
