import Foundation

/// A row in `activity_kinds`: a tab in Make a plan (sports, esports, later hackathons), with its own
/// copy and the features it turns on. From the server's catalog (`activity_catalog`); `builtIn` is
/// the fallback before the first fetch and offline.
nonisolated struct ActivityKind: Identifiable, Hashable, Sendable, Codable {
    let slug: String
    var labelEN: String
    var labelES: String
    /// Over the chips: "Sport", "Game".
    var itemLabelEN: String
    var itemLabelES: String
    /// The plan name field's placeholder.
    var titlePlaceholderEN: String
    var titlePlaceholderES: String
    /// A note suggestion such as "I have an extra ball". Nil leaves it out.
    var gearEN: String?
    var gearES: String?
    /// The `CourtKind` its activities draw when they don't name one.
    var defaultArt: String
    /// Round nights can be posted in this kind.
    var supportsRotation: Bool
    var sortOrder: Int
    var active = true

    var id: String { slug }

    /// The tab: "Sports".
    @MainActor var name: String { Self.isSpanish ? labelES : labelEN }
    /// Over the chips: "Sport".
    @MainActor var itemName: String { Self.isSpanish ? itemLabelES : itemLabelEN }
    @MainActor var titlePlaceholder: String { Self.isSpanish ? titlePlaceholderES : titlePlaceholderEN }
    @MainActor var gearLine: String? { Self.isSpanish ? gearES : gearEN }

    @MainActor private static var isSpanish: Bool { LanguageSettings.shared.language == "es" }

    static let sport = ActivityKind(
        slug: Activity.sportKind, labelEN: "Sports", labelES: "Deportes", itemLabelEN: "Sport", itemLabelES: "Deporte",
        titlePlaceholderEN: "e.g. Pickup after class", titlePlaceholderES: "p. ej., Cascarita después de clase",
        gearEN: "I have an extra ball", gearES: "Tengo un balón extra",
        defaultArt: CourtKind.generic.rawValue, supportsRotation: false, sortOrder: 1
    )

    static let esports = ActivityKind(
        slug: Activity.esportsKind, labelEN: "Esports", labelES: "Esports", itemLabelEN: "Game", itemLabelES: "Juego",
        titlePlaceholderEN: "e.g. Valorant night at the game room",
        titlePlaceholderES: "p. ej., Noche de Valorant en la sala de videojuegos",
        gearEN: "I have a spare headset", gearES: "Tengo audífonos extra",
        defaultArt: CourtKind.screen.rawValue, supportsRotation: true, sortOrder: 2
    )

    /// The same rows `20261126000000_activity_catalog` seeds.
    static let builtIn: [ActivityKind] = [sport, esports]

    /// A kind this build has never seen: named after its slug, with the sports copy and no extras.
    static func fallback(_ slug: String) -> ActivityKind {
        let name = slug.replacingOccurrences(of: "_", with: " ").capitalized
        return ActivityKind(
            slug: slug, labelEN: name, labelES: name, itemLabelEN: "Activity", itemLabelES: "Actividad",
            titlePlaceholderEN: sport.titlePlaceholderEN, titlePlaceholderES: sport.titlePlaceholderES,
            gearEN: nil, gearES: nil, defaultArt: CourtKind.generic.rawValue, supportsRotation: false,
            sortOrder: .max
        )
    }
}
