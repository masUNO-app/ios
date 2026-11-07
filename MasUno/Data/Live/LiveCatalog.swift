import Foundation
import Supabase

/// The live `AppConfigRepository`: what the app needs before sign-in, readable signed out.
final class LiveCatalog: AppConfigRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchAppConfig() async throws -> AppConfig {
        try await read {
            let rows: [AppConfigRow] = try await client.from("app_config").select().execute().value
            return AppConfig(rows: rows)
        }
    }

    func fetchActivities() async throws -> [Activity] {
        try await read {
            let rows: [ActivityRow] = try await client.from("activities").select().order("sort_order").execute().value
            return rows.map(\.activity)
        }
    }

    func fetchUniversities() async throws -> [University] {
        try await read {
            let rows: [UniversityRow] = try await client.from("university_lookup").select().order("name").execute().value
            return rows.compactMap(\.university)
        }
    }

    private func read<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw DomainError(serverCode: error.message)
        } catch is URLError {
            throw DomainError.offline
        }
    }
}

/// What can run on the real backend so far. Games, profiles and safety follow in B7.
enum LiveBackend {
    /// `nil` without real keys in `Config.xcconfig`.
    static func make(config: SupabaseConfig? = .current) -> (auth: LiveAuthService, catalog: LiveCatalog)? {
        guard let config else { return nil }
        let client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(flowType: .pkce, emitLocalSessionAsInitialSession: true))
        )
        return (LiveAuthService(client: client), LiveCatalog(client: client))
    }
}
