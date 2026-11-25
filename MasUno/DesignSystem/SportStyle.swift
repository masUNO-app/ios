import SwiftUI
import UIKit

/// Which drawing a sport gets behind its lineup (SPEC §7.7.3). The raw value is the name the catalog
/// uses (`activities.art`, `activity_kinds.default_art`), so the server can pick any of these.
nonisolated enum CourtKind: String, Hashable, Sendable, CaseIterable {
    case basketball, tennis, soccer, volleyball, padel
    /// Every esports game: a screen.
    case screen
    /// A sport the app has no drawing for yet: a plain court outline.
    case generic
}

extension Activity {
    /// The sport's color: its pin, court header, chat band, your bubbles, send button and chip.
    /// Ink is the label color on all of them. The catalog's hex first, then the asset color for a
    /// slug this build knows, then a neutral.
    var color: Color {
        if let light = AvatarPalette.rgb(hex: colorHex) {
            let dark = AvatarPalette.rgb(hex: colorDarkHex) ?? light
            return Color(AvatarPalette.color(light: light, dark: dark))
        }
        return assetColor
    }

    /// The colors this build ships, for a catalog row without one (or before the first fetch).
    private var assetColor: Color {
        switch slug {
        case "basketball": Color(.sportBasketball)
        case "tennis": Color(.sportTennis)
        case "soccer": Color(.sportSoccer)
        case "volleyball": Color(.sportVolleyball)
        case "padel": Color(.sportPadel)
        case "valorant": Color(.esportsValorant)
        case "csgo": Color(.esportsCSGO)
        case "league": Color(.esportsLeague)
        default: isEsport ? Color(.sportEsports) : Color(.sportOther)
        }
    }

    /// The catalog's drawing when this build has it, else the built-in choice for the slug.
    var court: CourtKind {
        if let art, let kind = CourtKind(rawValue: art) { return kind }
        switch slug {
        case "basketball": return .basketball
        case "tennis": return .tennis
        case "soccer": return .soccer
        case "volleyball": return .volleyball
        case "padel": return .padel
        default: return isEsport ? .screen : .generic
        }
    }
}

extension PersonSummary {
    /// One pastel per person, picked from the ID so it's the same on every screen and every phone.
    /// The signed-in person is `Theme.you` instead (see `PersonAvatar`).
    var color: Color {
        let rgb = AvatarPalette.person(id)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension EnvironmentValues {
    /// The signed-in person's ID, so tokens can draw them in `Theme.you`. Map annotations don't
    /// inherit the environment, so the map passes it in again.
    @Entry var currentUserID: UUID?
}
