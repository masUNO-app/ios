import Foundation

/// A row in `activities`. The list comes from the server's catalog (`activity_catalog`), kept by
/// `ActivityCatalog` and cached on the phone; `builtIn` is the fallback when it can't be loaded.
nonisolated struct Activity: Identifiable, Hashable, Sendable, Codable {
    let slug: String
    var kind = "sport"
    var labelEN: String
    var labelES: String
    var emoji: String
    var sortOrder: Int
    var postable = true
    var interestSelectable = true
    var active = true
    /// Its pin, header and chip color, "#RRGGBB". Nil uses the asset colors (`SportStyle.color`).
    var colorHex: String?
    /// Dark mode's, when it differs.
    var colorDarkHex: String?
    /// The `CourtKind` it draws. Nil uses the built-in choice for its slug.
    var art: String?

    var id: String { slug }

    /// The cache's keys. `color` is also what the notification extension reads (`CatalogBadges`).
    enum CodingKeys: String, CodingKey {
        case slug, kind, labelEN, labelES, emoji, sortOrder, postable, interestSelectable, active, art
        case colorHex = "color"
        case colorDarkHex = "colorDark"
    }

    static let sportKind = "sport"
    static let esportsKind = "esports"

    var isEsport: Bool { kind == Self.esportsKind }

    /// Display labels follow the in-app choice, independently of the phone's region.
    @MainActor var name: String {
        LanguageSettings.shared.language == "es" ? labelES : labelEN
    }

    /// The same rows and colors `20261126000000_activity_catalog` seeds.
    static let builtIn: [Activity] = [
        Activity(slug: "basketball", labelEN: "Basketball", labelES: "Básquetbol", emoji: "🏀", sortOrder: 1, colorHex: "#F2853A", art: "basketball"),
        Activity(slug: "tennis", labelEN: "Tennis", labelES: "Tenis", emoji: "🎾", sortOrder: 2, colorHex: "#C7D93D", art: "tennis"),
        Activity(slug: "soccer", labelEN: "Soccer", labelES: "Fútbol", emoji: "⚽️", sortOrder: 3, colorHex: "#3DB26F", art: "soccer"),
        Activity(slug: "volleyball", labelEN: "Volleyball", labelES: "Voleibol", emoji: "🏐", sortOrder: 4, colorHex: "#A99CF6", art: "volleyball"),
        Activity(slug: "padel", labelEN: "Padel", labelES: "Pádel", emoji: "🏓", sortOrder: 5, colorHex: "#56BDE8", art: "padel"),
    ]

    /// The esports titles the catalog seeds for 0.10 and later; the mocks serve them with `-esports YES`.
    static let esports: [Activity] = [
        Activity(slug: "valorant", kind: esportsKind, labelEN: "Valorant", labelES: "Valorant", emoji: "🎯", sortOrder: 100, colorHex: "#F06F7E"),
        Activity(slug: "csgo", kind: esportsKind, labelEN: "CS:GO", labelES: "CS:GO", emoji: "💣", sortOrder: 101, colorHex: "#E8B33A"),
        Activity(slug: "league", kind: esportsKind, labelEN: "League of Legends", labelES: "League of Legends", emoji: "🐉", sortOrder: 102, colorHex: "#4FC7B8"),
    ]
}
