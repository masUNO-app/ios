import Foundation

/// Each activity's emoji and color from the catalog the app last fetched (`CatalogCache` writes it
/// to the app group), for the notification extension, which has no catalog of its own.
nonisolated enum CatalogBadges {
    nonisolated struct Badge: Decodable, Sendable {
        let slug: String
        let emoji: String
        /// "#RRGGBB", or nil to use the built-in palette.
        let color: String?
    }

    /// Only the fields the extension needs; the app writes the whole `Catalog`.
    private nonisolated struct Snapshot: Decodable {
        let activities: [Badge]
    }

    /// Nil when the app hasn't cached a catalog, or it doesn't have this slug.
    static func badge(for slug: String) -> Badge? {
        guard let data = AppGroupStore.catalogData,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        return snapshot.activities.first { $0.slug == slug }
    }
}
