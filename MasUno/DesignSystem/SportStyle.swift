import SwiftUI

/// Which drawing a sport gets behind its lineup (SPEC §7.7.3).
nonisolated enum CourtKind: Hashable, Sendable {
    case basketball, tennis, soccer, volleyball, padel
    /// A sport the app has no drawing for yet: a plain court outline.
    case generic
}

extension Activity {
    /// The sport's color: its pin, court header, chat band, your bubbles, send button and chip.
    /// Ink is the label color on all of them. Sports added on the server later get a neutral.
    var color: Color {
        switch slug {
        case "basketball": Color(.sportBasketball)
        case "tennis": Color(.sportTennis)
        case "soccer": Color(.sportSoccer)
        case "volleyball": Color(.sportVolleyball)
        case "padel": Color(.sportPadel)
        default: Color(.sportOther)
        }
    }

    var court: CourtKind {
        switch slug {
        case "basketball": .basketball
        case "tennis": .tennis
        case "soccer": .soccer
        case "volleyball": .volleyball
        case "padel": .padel
        default: .generic
        }
    }
}

extension PersonSummary {
    /// One pastel per person, picked from the ID so it's the same on every screen and every phone.
    /// The signed-in person is `Theme.you` instead (see `PersonAvatar`).
    var color: Color {
        let sum = withUnsafeBytes(of: id.uuid) { $0.reduce(0) { $0 + Int($1) } }
        return Self.palette[sum % Self.palette.count]
    }

    private static let palette: [Color] = [
        Color(.person5), Color(.person1), Color(.person3), Color(.person4),
        Color(.person7), Color(.person6), Color(.person2),
    ]
}

extension EnvironmentValues {
    /// The signed-in person's ID, so tokens can draw them in `Theme.you`. Map annotations don't
    /// inherit the environment, so the map passes it in again.
    @Entry var currentUserID: UUID?
}
