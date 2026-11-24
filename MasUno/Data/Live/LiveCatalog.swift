import Foundation
import Supabase

/// The live `AppConfigRepository`: what the app needs before sign-in, readable signed out.
final class LiveCatalog: AppConfigRepository {
    private let client: SupabaseClient
    /// Shared with the game and profile repositories, so a fresh list reaches their rows too.
    let activities: ActivityCatalog

    init(client: SupabaseClient) {
        self.client = client
        activities = ActivityCatalog(cache: .appGroup) {
            try await liveRequest {
                let response: CatalogResponse = try await client
                    .rpc("activity_catalog", params: CatalogParams(appVersion: AppConfig.currentVersion))
                    .execute().value
                return response.catalog(fetchedAt: .now)
            }
        }
    }

    func fetchAppConfig() async throws -> AppConfig {
        try await liveRequest {
            let rows: [AppConfigRow] = try await client.from("app_config").select().execute().value
            return AppConfig(rows: rows)
        }
    }

    func fetchCatalog() async throws -> Catalog {
        try await activities.refresh()
    }

    var startingCatalog: Catalog { activities.catalog }

    func fetchUniversities() async throws -> [University] {
        try await liveRequest {
            let rows: [UniversityRow] = try await client.from("university_lookup").select().order("name").execute().value
            return rows.compactMap(\.university)
        }
    }
}

/// Everything behind the protocols on the real backend, sharing one client and session (B7).
struct LiveBackend {
    let auth: LiveAuthService
    let catalog: LiveCatalog
    let games: LiveGameRepository
    let profiles: LiveProfileRepository
    let safety: LiveSafetyRepository
    let chat: LiveChatRepository
    let notifications: LiveNotificationRepository

    /// `nil` without real keys in `Config.xcconfig`.
    static func make(config: SupabaseConfig? = .current) -> LiveBackend? {
        guard let config else { return nil }
        let client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(flowType: .pkce, emitLocalSessionAsInitialSession: true))
        )
        let catalog = LiveCatalog(client: client)
        return LiveBackend(
            auth: LiveAuthService(client: client),
            catalog: catalog,
            games: LiveGameRepository(client: client, activities: catalog.activities),
            profiles: LiveProfileRepository(client: client, activities: catalog.activities),
            safety: LiveSafetyRepository(client: client),
            chat: LiveChatRepository(client: client),
            notifications: LiveNotificationRepository(client: client)
        )
    }
}
