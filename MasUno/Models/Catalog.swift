import Foundation

/// Everything the server says about kinds of plans and their activities (`activity_catalog`), as one
/// value: what `ActivityCatalog` keeps, `CatalogCache` saves, and `GameStore` shows.
nonisolated struct Catalog: Hashable, Sendable, Codable {
    var kinds: [ActivityKind]
    var activities: [Activity]
    /// When it came from the server. Nil for the built-in one.
    var fetchedAt: Date?

    init(kinds: [ActivityKind], activities: [Activity], fetchedAt: Date? = nil) {
        self.kinds = kinds
        // An activity without its own drawing takes its kind's, so a new kind's art comes from the server.
        self.activities = activities.map { activity in
            guard activity.art == nil, let kind = kinds.first(where: { $0.slug == activity.kind }) else { return activity }
            var resolved = activity
            resolved.art = kind.defaultArt
            return resolved
        }
        self.fetchedAt = fetchedAt
    }

    /// Before the first fetch, and when it fails with nothing cached: today's sports.
    static let builtIn = Catalog(kinds: ActivityKind.builtIn, activities: Activity.builtIn)

    func activity(slug: String) -> Activity? {
        activities.first { $0.slug == slug }
    }

    /// The kind for a slug; one this build has never seen still gets a name.
    func kind(_ slug: String) -> ActivityKind {
        kinds.first { $0.slug == slug } ?? .fallback(slug)
    }
}
