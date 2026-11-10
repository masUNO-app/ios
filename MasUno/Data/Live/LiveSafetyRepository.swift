import Foundation
import Supabase

/// The live `SafetyRepository` (B7): the `report`, `block`, `unblock` and `my_blocks` RPCs.
final class LiveSafetyRepository: SafetyRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws {
        try await liveRequest {
            _ = try await client.rpc("report", params: ReportParams(target: target, reason: reason, note: note)).execute()
        }
    }

    func block(userID: UUID) async throws {
        try await liveRequest {
            _ = try await client.rpc("block", params: UserIDParams(userID: userID)).execute()
        }
    }

    func unblock(userID: UUID) async throws {
        try await liveRequest {
            _ = try await client.rpc("unblock", params: UserIDParams(userID: userID)).execute()
        }
    }

    func fetchBlockedPeople() async throws -> [PersonSummary] {
        try await liveRequest {
            let rows: [BlockedPersonRow] = try await client.rpc("my_blocks").execute().value
            return rows.map(\.person)
        }
    }
}
