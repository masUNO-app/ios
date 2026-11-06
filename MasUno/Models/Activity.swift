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

    /// Follows the app's language, not the phone's region, so 1.0 (English only)
    /// doesn't show a Spanish sport name in an English screen.
    var name: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("es") == true ? labelES : labelEN
    }

    static let builtIn: [Activity] = [
        Activity(slug: "basketball", labelEN: "Basketball", labelES: "Básquetbol", emoji: "🏀", sortOrder: 1),
        Activity(slug: "tennis", labelEN: "Tennis", labelES: "Tenis", emoji: "🎾", sortOrder: 2),
        Activity(slug: "soccer", labelEN: "Soccer", labelES: "Fútbol", emoji: "⚽️", sortOrder: 3),
        Activity(slug: "volleyball", labelEN: "Volleyball", labelES: "Voleibol", emoji: "🏐", sortOrder: 4),
        Activity(slug: "padel", labelEN: "Padel", labelES: "Pádel", emoji: "🏓", sortOrder: 5),
    ]
}
