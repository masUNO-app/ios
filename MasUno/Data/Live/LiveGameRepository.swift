import Foundation
import OSLog
import Supabase

/// The live `GameRepository` (B7): reads `game_cards`, `game_attendees` and `game_activity`, and writes
/// through the game RPCs, which return the updated `game_cards` row (`docs/API.md`).
final class LiveGameRepository: GameRepository {
    private let client: SupabaseClient
    private let activities: ActivityCatalog
    private static let logger = Logger(subsystem: "com.masuno.app", category: "GameChanges")

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

    /// `guest_games` runs as the anon role when signed out; the server applies the map's filters and order.
    func fetchGuestGames(campus: UUID) async throws -> [Game] {
        try await liveRequest {
            let rows: [GuestGameRow] = try await client.rpc("guest_games", params: GuestGamesParams(campus: campus))
                .execute().value
            await activities.loadIfNeeded()
            return rows.map { $0.game(activity: activities.activity(slug:)) }
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

    func fetchBookmarkedGames() async throws -> [Game] {
        let cutoff = Date.now.addingTimeInterval(-14 * 24 * 3600)
        return try await games {
            try await client.from("game_cards").select()
                .eq("is_bookmarked", value: true)
                .gt("ends_at", value: ServerTime.string(from: cutoff))
                .order("starts_at")
                .execute().value
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

    /// A round night sends its rounds too (`20261126000100_round_nights`).
    func createGame(_ draft: GameDraft) async throws -> Game {
        try await write("create_game", GameDraftParams(draft))
    }

    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game {
        try await write("update_game", GameDraftParams(id: id, draft))
    }

    /// `game_rotation`: the rounds, and the groups of each round that's out. The server picks a
    /// round's groups when it comes out and keeps them.
    func fetchRotation(gameID: UUID) async throws -> RotationPlan {
        try await liveRequest {
            let response: RotationResponse = try await client
                .rpc("game_rotation", params: GameRotationParams(gameID: gameID))
                .execute().value
            return response.plan
        }
    }

    // MARK: Props (1.0)

    func propsToGive(gameID: UUID, round: Int?) async throws -> PropsToGive {
        try await liveRequest {
            let response: PropsToGiveResponse = try await client
                .rpc("props_to_give", params: PropsParams(gameID: gameID, round: round, props: nil))
                .execute().value
            return response.props
        }
    }

    func giveProps(gameID: UUID, round: Int?, _ props: [UUID: Set<Prop>]) async throws -> Int {
        let body = Dictionary(uniqueKeysWithValues: props.map { ($0.key.uuidString.lowercased(), $0.value.map(\.rawValue).sorted()) })
        return try await liveRequest {
            let response: GivePropsResponse = try await client
                .rpc("give_props", params: PropsParams(gameID: gameID, round: round, props: body))
                .execute().value
            return response.sent
        }
    }

    func propCounts(for people: [UUID]) async throws -> [UUID: [Prop: Int]] {
        guard !people.isEmpty else { return [:] }
        return try await liveRequest {
            let rows: [PropCountRow] = try await client
                .rpc("prop_counts", params: PropCountsParams(userIDs: Array(people.prefix(50))))
                .execute().value
            return PropCountRow.counts(rows)
        }
    }

    func myProps(gameID: UUID) async throws -> PropTally {
        try await liveRequest {
            let response: MyPropsResponse = try await client
                .rpc("my_props_for_game", params: PropsGameParams(gameID: gameID))
                .execute().value
            return response.tally
        }
    }

    func propsLeaderboard(prop: Prop, filter: String?) async throws -> PropsLeaderboard {
        try await liveRequest {
            let response: PropsLeaderboardResponse = try await client
                .rpc("props_leaderboard", params: PropsLeaderboardParams(prop: prop.rawValue, filter: filter))
                .execute().value
            return response.leaderboard
        }
    }

    func propsLeaderboardOptIn() async throws -> Bool {
        try await liveRequest {
            try await client.rpc("props_leaderboard_opt_in").execute().value
        }
    }

    func setPropsLeaderboardOptIn(_ on: Bool) async throws -> Bool {
        try await liveRequest {
            try await client.rpc("set_props_leaderboard", params: PropsOptInParams(on: on)).execute().value
        }
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

    func setBookmark(id: UUID, on: Bool) async throws -> Game {
        try await write("set_bookmark", BookmarkParams(id: id, on: on))
    }

    func setSpotAlert(id: UUID, on: Bool) async throws -> Game {
        try await write("set_spot_alert", SpotAlertParams(id: id, on: on))
    }

    func importBookmarks(ids: [UUID], alertIDs: [UUID]) async throws {
        _ = try await liveRequest {
            try await client.rpc(
                "import_bookmarks", params: ImportBookmarksParams(ids: ids, alertIDs: alertIDs)
            ).execute()
        }
    }

    /// Yields once per ping on the campus's games channel. The stream ends if the channel can't
    /// connect, so `GameStore` re-opens it.
    func changes(campus: UUID) -> AsyncStream<GameChanges> {
        let client = client
        return AsyncStream { continuation in
            let listener = Task {
                let channel = client.channel(gamesChannelName(campus: campus)) { $0.isPrivate = true }
                let pings = channel.broadcastStream(event: "changed")
                do {
                    try await channel.subscribeWithError()
                    for await message in pings { continuation.yield(Self.changes(in: message)) }
                } catch {
                    Self.logger.error("Games channel didn't connect: \(error.localizedDescription, privacy: .public)")
                }
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in listener.cancel() }
        }
    }

    /// `{"ids": [...]}`, or `{}` when the server had too many to list.
    private static func changes(in message: JSONObject) -> GameChanges {
        guard let ids = message["payload"]?.objectValue?["ids"]?.arrayValue else { return .unlisted }
        return .games(Set(ids.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }))
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
