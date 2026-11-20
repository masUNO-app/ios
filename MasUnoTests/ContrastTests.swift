import Testing
import UIKit
@testable import masUNO

/// WCAG contrast for the color pairs the app draws (A11Y-15), computed from the asset catalog in light,
/// dark and both Increase Contrast variants. This replaces the UI audit's contrast pass, which measured
/// whatever showed through the glass or the map and couldn't tell a regression from noise.
nonisolated struct ContrastTests {
    enum Mode: String, CaseIterable, CustomTestStringConvertible {
        case light, dark, lightHigh, darkHigh

        var traits: UITraitCollection {
            UITraitCollection { traits in
                traits.userInterfaceStyle = self == .dark || self == .darkHigh ? .dark : .light
                traits.accessibilityContrast = self == .lightHigh || self == .darkHigh ? .high : .normal
            }
        }

        var testDescription: String { rawValue }
    }

    /// A label color over a fill, and the ratio it needs: 4.5 for text (AA), 3 for non-text edges and
    /// controls (WCAG 1.4.11).
    struct Pair: CustomTestStringConvertible, Sendable {
        let foreground: String
        let background: String
        let name: String
        var minimum = 4.5

        var testDescription: String { name }
    }

    /// Text on the app's surfaces, as Theme documents each token.
    static let text: [Pair] = [
        Pair(foreground: "Ink", background: "Background", name: "ink on background"),
        Pair(foreground: "Ink", background: "Card", name: "ink on card"),
        Pair(foreground: "Ink", background: "Surface2", name: "ink on surface2"),
        Pair(foreground: "Ink", background: "Paper", name: "ink on paper (host's note)"),
        Pair(foreground: "Ink", background: "AccentSoft", name: "ink on accentSoft (secondary pill)"),
        Pair(foreground: "Muted", background: "Background", name: "muted on background"),
        Pair(foreground: "Muted", background: "Card", name: "muted on card"),
        Pair(foreground: "Muted", background: "RowSeparator", name: "muted on the day pill"),
        Pair(foreground: "MutedLarge", background: "Background", name: "mutedLarge on background"),
        Pair(foreground: "MutedLarge", background: "Card", name: "mutedLarge on card"),
        Pair(foreground: "AccentText", background: "Background", name: "accentText on background"),
        Pair(foreground: "AccentText", background: "Card", name: "accentText on card"),
        Pair(foreground: "DestructiveText", background: "Background", name: "destructiveText on background"),
        Pair(foreground: "DestructiveText", background: "Card", name: "destructiveText on card"),
        Pair(foreground: "Error", background: "Background", name: "error on background"),
        Pair(foreground: "Error", background: "Card", name: "error on card"),
    ]

    /// Controls and edges, which need 3:1 against what they sit on.
    static let nonText: [Pair] = [
        Pair(foreground: "AccentColor", background: "Background", name: "accent fill (toggles, primary pill) on background", minimum: 3),
        Pair(foreground: "AccentColor", background: "Card", name: "accent fill on card", minimum: 3),
    ]

    /// Sport, person and You colors keep dark ink in dark mode (`inkOnColor()` forces light), so only the
    /// light variants apply.
    static let onColor: [String] = [
        "Person1", "Person2", "Person3", "Person4", "Person5", "Person6", "Person7", "You",
        "SportBasketball", "SportOther", "SportPadel", "SportSoccer", "SportTennis", "SportVolleyball",
    ]

    @Test(arguments: text + nonText, Mode.allCases)
    func pairMeetsItsMinimum(_ pair: Pair, mode: Mode) {
        let ratio = Self.ratio(pair.foreground, on: pair.background, in: mode.traits)
        #expect(ratio >= pair.minimum, "\(pair.name) in \(mode.rawValue): \(Self.format(ratio)):1, needs \(pair.minimum)")
    }

    /// White labels on the primary and destructive fills, which stay white in dark mode.
    @Test(arguments: ["AccentColor", "Destructive"], Mode.allCases)
    func whiteLabelOnFill(_ fill: String, mode: Mode) {
        let ratio = Self.ratio(.white, on: Self.color(fill, mode.traits))
        #expect(ratio >= 4.5, "white on \(fill) in \(mode.rawValue): \(Self.format(ratio)):1")
    }

    @Test(arguments: onColor, [Mode.light, .lightHigh])
    func inkOnPersonAndSportColors(_ fill: String, mode: Mode) {
        let ratio = Self.ratio("Ink", on: fill, in: mode.traits)
        #expect(ratio >= 4.5, "ink on \(fill) in \(mode.rawValue): \(Self.format(ratio)):1")
    }

    /// The hairline is ink at 10% by default (decorative), and a solid 3:1 edge under Increase Contrast.
    @Test(arguments: [Mode.lightHigh, .darkHigh])
    func hairlineIsAVisibleEdgeUnderIncreaseContrast(mode: Mode) {
        let ratio = Self.ratio("Hairline", on: "Background", in: mode.traits)
        #expect(ratio >= 3, "hairline in \(mode.rawValue): \(Self.format(ratio)):1")
    }

    @Test(arguments: Mode.allCases)
    func surfacesAreOpaque(mode: Mode) {
        for surface in ["Background", "Card", "Surface2", "Paper", "AccentSoft", "RowSeparator"] {
            #expect(Self.alpha(of: Self.color(surface, mode.traits)) == 1, "\(surface) in \(mode.rawValue)")
        }
    }

    // MARK: WCAG 2.x

    /// A named color from the app's asset catalog. The tests run inside the app, so `Bundle.main` is it.
    static func color(_ name: String, _ traits: UITraitCollection) -> UIColor {
        guard let color = UIColor(named: name, in: .main, compatibleWith: traits) else {
            Issue.record("No color named \(name) in the asset catalog")
            return .clear
        }
        return color.resolvedColor(with: traits)
    }

    static func ratio(_ foreground: String, on background: String, in traits: UITraitCollection) -> Double {
        ratio(color(foreground, traits),
              on: color(background, traits))
    }

    /// A translucent foreground is composited over the background first, as it draws.
    static func ratio(_ foreground: UIColor, on background: UIColor) -> Double {
        let back = components(of: background)
        let front = components(of: foreground)
        let mixed = (0..<3).map { front.rgb[$0] * front.alpha + back.rgb[$0] * (1 - front.alpha) }
        let lighter = max(luminance(mixed), luminance(back.rgb))
        let darker = min(luminance(mixed), luminance(back.rgb))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// sRGB components, clamped: the catalog's colors are all sRGB.
    private static func components(of color: UIColor) -> (rgb: [Double], alpha: Double) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ([red, green, blue].map { min(max(Double($0), 0), 1) }, Double(alpha))
    }

    private static func alpha(of color: UIColor) -> Double { components(of: color).alpha }

    private static func format(_ ratio: Double) -> String { String(format: "%.2f", ratio) }
}
