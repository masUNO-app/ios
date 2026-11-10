import Foundation
import Supabase

/// The live `ProfileRepository` (B7): your row in `my_profile`, edited through `complete_profile`.
final class LiveProfileRepository: ProfileRepository {
    private let client: SupabaseClient
    private let activities: ActivityCatalog

    init(client: SupabaseClient, activities: ActivityCatalog) {
        self.client = client
        self.activities = activities
    }

    func fetchMyProfile() async throws -> Profile? {
        try await profile {
            try await client.from("my_profile").select().execute().value
        }
    }

    /// `complete_profile` updates an existing profile and never changes its campus (`docs/API.md`).
    func updateProfile(_ input: ProfileInput) async throws -> Profile {
        let updated = try await profile {
            try await client.rpc("complete_profile", params: CompleteProfileParams(input)).execute().value
        }
        guard let updated else { throw DomainError.notAuthenticated }
        return updated
    }

    private func profile(_ query: () async throws -> [MyProfileRow]) async throws -> Profile? {
        try await liveRequest {
            guard let row = try await query().first else { return nil }
            await activities.loadIfNeeded()
            return row.profile(activity: activities.activity(slug:))
        }
    }
}
