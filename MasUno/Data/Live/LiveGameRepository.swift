import Foundation
import Supabase

/// The live `GameRepository` (B7): reads `game_cards`, `game_attendees` and `game_activity`, and writes
/// through the game RPCs, which return the updated `game_cards` row (`docs/API.md`).
final class LiveGameRepository: GameRepository {
    private let client: SupabaseClient
    private let activities: ActivityCatalog

    init(client: SupabaseClient, activities: ActivityCatalog) {
        self.client = client
        self.activities = activities
    }

    func fetchMapGames() async throws -> [Game] {
        let now = Date.now
        return try await games {
            try await client.from("game_cards").select()
                .is("cancelled_at", value: nil)
                .gt("ends_at", value: ServerTime.string(from: now))
                .lt("starts_at", value: ServerTime.string(from: now.addingTimeInterval(GameDraft.postingWindow)))
                .gt("spots_left", value: 0)
                .order("sort_at", ascending: false)
                .execute().value
        }
    }

    func fetchMyGames() async throws -> [Game] {
        let cutoff = Date.now.addingTimeInterval(-14 * 24 * 3600)
        return try await games {
            try await client.from("game_cards").select()
                .not("my_role", operator: .is, value: "null")
                .gt("ends_at", value: ServerTime.string(from: cutoff))
                .order("starts_at")
                .execute().value
        }
    }

    func fetchGame(id: UUID) async throws -> Game {
        let found = try await games {
            try await client.from("game_cards").select().eq("id", value: id.uuidString).execute().value
        }
        guard let game = found.first else { throw DomainError.notFound }
        return game
    }

    func fetchGames(ids: [UUID]) async throws -> [Game] {
        guard !ids.isEmpty else { return [] }
        return try await games {
            try await client.from("game_cards").select().in("id", values: ids.map(\.uuidString)).execute().value
        }
    }

    func fetchAttendees(gameID: UUID) async throws -> [Attendee] {
        try await liveRequest {
            let rows: [AttendeeRow] = try await client.from("game_attendees").select()
                .eq("event_id", value: gameID.uuidString)
                .execute().value
            // Host first, then in the order people joined.
            return rows.map(\.attendee).sorted {
                ($0.role == .host ? 0 : 1, $0.joinedAt) < ($1.role == .host ? 0 : 1, $1.joinedAt)
            }
        }
    }

    func fetchActivity(gameID: UUID) async throws -> [GameActivityEntry] {
        try await liveRequest {
            let rows: [GameActivityRow] = try await client.from("game_activity").select()
                .eq("event_id", value: gameID.uuidString)
                .order("at")
                .execute().value
            return rows.compactMap(\.entry)
        }
    }

    func createGame(_ draft: GameDraft) async throws -> Game {
        try await write("create_game", GameDraftParams(draft))
    }

    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game {
        try await write("update_game", GameDraftParams(id: id, draft))
    }

    func cancelGame(id: UUID) async throws -> Game {
        try await write("cancel_game", GameIDParams(id: id))
    }

    func joinGame(id: UUID) async throws -> Game {
        try await write("join_game", GameIDParams(id: id))
    }

    func leaveGame(id: UUID) async throws -> Game {
        try await write("leave_game", GameIDParams(id: id))
    }

    // MARK: Helpers

    private func games(_ query: () async throws -> [GameCardRow]) async throws -> [Game] {
        try await liveRequest {
            let rows = try await query()
            await activities.loadIfNeeded()
            return rows.map { $0.game(activity: activities.activity(slug:)) }
        }
    }

    /// Game RPCs return `setof game_cards`: one row, or none if RLS hides the result from you.
    private func write(_ function: String, _ params: some Encodable & Sendable) async throws -> Game {
        let rows = try await games {
            try await client.rpc(function, params: params).execute().value
        }
        guard let game = rows.first else { throw DomainError.notFound }
        return game
    }
}
