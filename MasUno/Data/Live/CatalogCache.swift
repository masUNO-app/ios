import Foundation

/// The last catalog the server sent, kept in the app group as JSON, so a cold start or an offline
/// launch begins from it instead of the built-in list, and the notification extension can draw a
/// sport this build doesn't know (`CatalogBadges`).
nonisolated struct CatalogCache: Sendable {
    let read: @Sendable () -> Data?
    let write: @Sendable (Data?) -> Void

    /// The app group, shared with `masUNONotifications`.
    static let appGroup = CatalogCache(read: { AppGroupStore.catalogData }, write: { AppGroupStore.catalogData = $0 })

    /// In memory, for tests.
    static func memory() -> CatalogCache {
        let box = Box()
        return CatalogCache(read: { box.data }, write: { box.data = $0 })
    }

    /// Nil when nothing was saved, it can't be read (a build with a different shape), or it's empty.
    func load() -> Catalog? {
        guard let data = read(), let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              !catalog.activities.isEmpty
        else { return nil }
        return catalog
    }

    func save(_ catalog: Catalog) {
        write(try? JSONEncoder().encode(catalog))
    }

    private final class Box: @unchecked Sendable {
        var data: Data?
    }
}
