import Foundation

/// The `activities` list the live repositories use to turn `activity_slug` and `interests` into
/// `Activity` values (B7). Starts as `Activity.builtIn`, loads from the server once, and keeps the
/// built-in list if that fails, so a game row never fails to show because of its sport.
final class ActivityCatalog {
    private(set) var activities: [Activity]
    private var isLoaded = false
    private var inFlight: Task<[Activity], any Error>?
    private let fetch: () async throws -> [Activity]

    init(activities: [Activity] = Activity.builtIn, fetch: @escaping () async throws -> [Activity]) {
        self.activities = activities
        self.fetch = fetch
    }

    /// The sport for a slug. One this build has never seen still shows, by name, but can't be posted
    /// or picked as an interest.
    func activity(slug: String) -> Activity {
        activities.first { $0.slug == slug } ?? Self.placeholder(slug: slug)
    }

    /// Loads once. Until a load succeeds, each call tries again.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        _ = try? await refresh()
    }

    /// Fetches the list, keeps it if it isn't empty, and returns what's kept.
    @discardableResult
    func refresh() async throws -> [Activity] {
        let task = inFlight ?? Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }
        let fetched = try await task.value
        if !fetched.isEmpty {
            activities = fetched
            isLoaded = true
        }
        return activities
    }

    static func placeholder(slug: String) -> Activity {
        let name = slug.replacingOccurrences(of: "_", with: " ").capitalized
        return Activity(
            slug: slug, labelEN: name, labelES: name, emoji: "🏅", sortOrder: .max,
            postable: false, interestSelectable: false
        )
    }
}
