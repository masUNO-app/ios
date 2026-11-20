import Foundation

/// A row in `activities`. The list comes from the server, cached by `ActivityCatalog` (B7);
/// `builtIn` is the fallback when it can't be loaded.
nonisolated struct Activity: Identifiable, Hashable, Sendable {
    let slug: String
    var kind = "sport"
    var labelEN: String
    var labelES: String
    var emoji: String
    var sortOrder: Int
    var postable = true
    var interestSelectable = true
    var active = true

    var id: String { slug }

    static let sportKind = "sport"
    static let esportsKind = "esports"

    var isEsport: Bool { kind == Self.esportsKind }

    /// A kind's tab in Make a plan: "Sports", "Esports". A kind the server adds later shows by name.
    @MainActor static func kindName(_ kind: String) -> String {
        switch kind {
        case sportKind: String.app("Sports")
        case esportsKind: String.app("Esports")
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// What one of a kind is called, over its chips: "Sport", "Game", "Activity".
    @MainActor static func itemName(_ kind: String) -> String {
        switch kind {
        case sportKind: String.app("Sport")
        case esportsKind: String.app("Game")
        default: String.app("Activity")
        }
    }

    /// Display labels follow the in-app choice, independently of the phone's region.
    @MainActor var name: String {
        LanguageSettings.shared.language == "es" ? labelES : labelEN
    }

    static let builtIn: [Activity] = [
        Activity(slug: "basketball", labelEN: "Basketball", labelES: "Básquetbol", emoji: "🏀", sortOrder: 1),
        Activity(slug: "tennis", labelEN: "Tennis", labelES: "Tenis", emoji: "🎾", sortOrder: 2),
        Activity(slug: "soccer", labelEN: "Soccer", labelES: "Fútbol", emoji: "⚽️", sortOrder: 3),
        Activity(slug: "volleyball", labelEN: "Volleyball", labelES: "Voleibol", emoji: "🏐", sortOrder: 4),
        Activity(slug: "padel", labelEN: "Padel", labelES: "Pádel", emoji: "🏓", sortOrder: 5),
    ]

    /// Games for esports nights (`-esports YES`, mock only), each in its own color like the sports.
    static let esports: [Activity] = [
        Activity(slug: "valorant", kind: esportsKind, labelEN: "Valorant", labelES: "Valorant", emoji: "🎯", sortOrder: 100),
        Activity(slug: "csgo", kind: esportsKind, labelEN: "CS:GO", labelES: "CS:GO", emoji: "💣", sortOrder: 101),
        Activity(slug: "league", kind: esportsKind, labelEN: "League of Legends", labelES: "League of Legends", emoji: "🐉", sortOrder: 102),
    ]
}
