import SwiftUI
import UIKit

/// 1.0 tokens, "Room for one more" (SPEC §7.7.2). The colors live in `Assets.xcassets` (Colors/
/// and AccentColor) as named color sets, so they match the Figma variables one-to-one and can get
/// dark variants later. Views use these, never raw colors. Light mode only.
enum Theme {
    // MARK: Colors

    /// The one action color: primary buttons, toggles, "You" tokens, Host labels. White label only here.
    static let accent = Color(.accent)
    /// Mint: secondary buttons ("Details", "Not now", "Leave").
    static let accentSoft = Color(.accentSoft)
    /// Screens and sheets.
    static let background = Color(.background)
    /// Cards, popups, dialogs, other people's chat bubbles.
    static let card = Color(.card)
    /// Secondary fills: safety notes, cancelled and past card headers.
    static let surface2 = Color(.surface2)
    /// Titles and body text. Also the label on every sport and person color.
    static let ink = Color(.ink)
    /// Secondary text at any size.
    static let muted = Color(.muted)
    /// Lighter secondary text, only for ≥ 18 pt or ≥ 14 pt bold.
    static let mutedLarge = Color(.mutedLarge)
    /// Leave game, Cancel game, Sign out, Delete account.
    static let destructive = Color(.destructive)
    /// Field errors.
    static let error = Color(.error)
    /// The signed-in person, everywhere. Kept out of the other people's palette.
    static let you = Color(.you)
    /// Opaque row separators and the day pill.
    static let separator = Color(.separator)

    // Derived from the tokens above.

    /// Hairline border on cards and fields.
    static let hairline = ink.opacity(0.1)
    /// Soft drop shadow under pins and floating cards.
    static let shadow = ink.opacity(0.18)
    /// Label color on `accent` and `destructive` fills.
    static let onAccent = Color.white
    /// Scrim behind a dialog.
    static let scrim = ink.opacity(0.35)
    /// Soft red behind a destructive dialog's icon.
    static let destructiveSoft = destructive.opacity(0.12)

    // MARK: Metrics

    enum Radius {
        /// Small tiles: settings icons, search results, map thumbnails.
        static let tile: CGFloat = 12
        /// Fields and grouped rows.
        static let field: CGFloat = 18
        /// Cards.
        static let card: CGFloat = 22
        /// Popups and dialogs.
        static let dialog: CGFloat = 30
        /// The content sheet over a court header.
        static let sheet: CGFloat = 26
    }

    /// Full-width pill button height.
    static let buttonHeight: CGFloat = 50
    /// Screen side margin.
    static let gutter: CGFloat = 20
    /// Widest a phone-sized column gets on big screens (iPad, iPhone Duo unfolded).
    static let columnWidth: CGFloat = 560

    // MARK: UIKit appearance

    /// Rounded type for the bars and controls SwiftUI hands to UIKit (SPEC §7.7.2, R7-10).
    static func applyAppearance() {
        let ink = UIColor(resource: .ink)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFont.rounded(.largeTitle, weight: .bold), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: UIFont.rounded(.headline, weight: .bold), .foregroundColor: ink]

        // Me · Going / Hosting: mint track, card-white selection.
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(resource: .accentSoft)
        segmented.selectedSegmentTintColor = UIColor(resource: .card)
        let font = UIFont.rounded(.footnote, weight: .bold)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(resource: .muted), .font: font], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: ink, .font: font], for: .selected)
    }
}

extension UIFont {
    /// SF Pro Rounded at a text style's size, following Dynamic Type.
    static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: 0))
    }
}

extension Font {
    /// SF Pro Rounded in a text style. Body copy is medium, as in the Figma.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .medium) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// A fixed size, for text inside tokens and pins that scale with their circle.
    static func rounded(size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Card surface: `card` fill, rounded corners, hairline border.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline))
    }

    /// Keeps a phone-width column centered on big screens.
    func readableColumn() -> some View {
        frame(maxWidth: Theme.columnWidth).frame(maxWidth: .infinity)
    }
}

extension Color {
    /// Art-only colors (court lines and fills). Everything else comes from the asset catalog.
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
