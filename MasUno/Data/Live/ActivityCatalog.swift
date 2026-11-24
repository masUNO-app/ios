import Foundation

/// The catalog the live repositories use to turn `activity_slug` and `interests` into `Activity`
/// values (B7). Starts from the cached catalog, or the built-in one, loads from the server, and keeps
/// what it has if that fails, so a game row never fails to show because of its sport.
final class ActivityCatalog {
    private(set) var catalog: Catalog
    private var isLoaded = false
    private var inFlight: Task<Catalog, any Error>?
    private let fetch: () async throws -> Catalog
    private let cache: CatalogCache?

    var activities: [Activity] { catalog.activities }

    /// - Parameters:
    ///   - catalog: Where to start; by default the cache, then the built-in catalog.
    ///   - cache: Where fetched catalogs are kept. Nil keeps nothing (tests).
    init(catalog: Catalog? = nil, cache: CatalogCache? = nil, fetch: @escaping () async throws -> Catalog) {
        self.catalog = catalog ?? cache?.load() ?? .builtIn
        self.cache = cache
        self.fetch = fetch
    }

    /// The activity for a slug. One this build has never seen still shows, by name, but can't be
    /// posted or picked as an interest.
    func activity(slug: String) -> Activity {
        catalog.activity(slug: slug) ?? Self.placeholder(slug: slug)
    }

    /// Loads once. Until a load succeeds, each call tries again.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        _ = try? await refresh()
    }

    /// Fetches the catalog, keeps and caches it if it has activities, and returns what's kept.
    @discardableResult
    func refresh() async throws -> Catalog {
        let task = inFlight ?? Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }
        let fetched = try await task.value
        if !fetched.activities.isEmpty {
            catalog = fetched
            isLoaded = true
            cache?.save(fetched)
        }
        return catalog
    }

    static func placeholder(slug: String) -> Activity {
        let name = slug.replacingOccurrences(of: "_", with: " ").capitalized
        return Activity(
            slug: slug, labelEN: name, labelES: name, emoji: "🏅", sortOrder: .max,
            postable: false, interestSelectable: false
        )
    }
}
