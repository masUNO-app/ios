import Foundation
import Supabase

/// The live `ChatRepository` (E26): reads `game_messages` and `chat_unread`, writes through the chat
/// RPCs, and listens on the game's private Realtime channel (`docs/API.md`, Group chat).
final class LiveChatRepository: ChatRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        try await liveRequest {
            var query = client.from("game_messages").select().eq("event_id", value: gameID.uuidString)
            if let before {
                // Filters send milliseconds, so reach a little past `before` rather than skip a
                // message from the same millisecond. The caller drops the repeats.
                query = query.lte("created_at", value: ServerTime.string(from: before.addingTimeInterval(0.001)))
            }
            let rows: [GameMessageRow] = try await query
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .limit(limit)
                .execute().value
            return rows.reversed().map(\.message)
        }
    }

    func fetchMessages(gameID: UUID, before cursor: ChatMessageCursor, limit: Int) async throws -> [ChatMessage] {
        try await liveRequest {
            let time = cursor.serverCreatedAt ?? ServerTime.string(from: cursor.createdAt)
            let rows: [GameMessageRow] = try await client.from("game_messages").select()
                .eq("event_id", value: gameID.uuidString)
                .or("created_at.lt.\(time),and(created_at.eq.\(time),id.lt.\(cursor.id.uuidString))")
                .order("created_at", ascending: false).order("id", ascending: false)
                .limit(limit).execute().value
            return rows.reversed().map(\.message)
        }
    }

    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage] {
        try await liveRequest {
            let pageSize = 200
            var all: [ChatMessage] = []
            var cursor: ChatMessageCursor?
            while true {
                try Task.checkCancellation()
                var query = client.from("game_messages").select()
                    .eq("event_id", value: gameID.uuidString)
                    .gte("created_at", value: ServerTime.string(from: since))
                if let cursor {
                    let time = cursor.serverCreatedAt ?? ServerTime.string(from: cursor.createdAt)
                    query = query.or("created_at.gt.\(time),and(created_at.eq.\(time),id.gt.\(cursor.id.uuidString))")
                }
                let rows: [GameMessageRow] = try await query.order("created_at").order("id")
                    .limit(pageSize).execute().value
                let page = rows.map(\.message)
                all += page
                guard page.count == pageSize, let last = page.last else { return all }
                cursor = ChatMessageCursor(last)
            }
        }
    }

    func sendMessage(gameID: UUID, body: String, clientID: UUID, mentions: [UUID]) async throws -> ChatMessage {
        try await liveRequest {
            let params = SendMessageParams(gameID: gameID, body: body, clientID: clientID, mentions: mentions)
            let rows: [GameMessageRow] = try await client
                .rpc("send_message", params: params)
                .execute().value
            guard let row = rows.first else { throw DomainError.notFound }
            return row.message
        }
    }

    func acceptChatRules() async throws {
        try await liveRequest {
            _ = try await client.rpc("accept_chat_rules").execute()
        }
    }

    func markRead(gameID: UUID) async throws {
        try await liveRequest {
            _ = try await client.rpc("mark_chat_read", params: ChatGameParams(gameID: gameID)).execute()
        }
    }

    func fetchUnreadCounts() async throws -> [UUID: Int] {
        try await liveRequest {
            let rows: [ChatUnreadRow] = try await client.from("chat_unread").select().execute().value
            return Dictionary(rows.map { ($0.eventID, $0.unreadCount) }, uniquingKeysWith: +)
        }
    }

    /// The server only lets people in the game join the channel. If joining fails, the stream ends
    /// and the chat keeps up through its timer.
    func updates(gameID: UUID) -> AsyncStream<ChatUpdate> {
        let client = client
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let listener = Task {
                let channel = client.channel(chatChannelName(gameID: gameID)) { $0.isPrivate = true }
                let messages = channel.broadcastStream(event: "message")
                let activity = channel.broadcastStream(event: "activity")
                do {
                    try await channel.subscribeWithError()
                    continuation.yield(.connected)
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { for await _ in messages { continuation.yield(.message) } }
                        group.addTask { for await _ in activity { continuation.yield(.activity) } }
                        group.addTask {
                            var connected = true
                            for await status in channel.statusChange {
                                switch status {
                                case .subscribed:
                                    if !connected { continuation.yield(.connected) }
                                    connected = true
                                case .subscribing:
                                    connected = false
                                    continuation.yield(.disconnected)
                                case .unsubscribed, .unsubscribing:
                                    continuation.yield(.disconnected)
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                } catch {}
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in listener.cancel() }
        }
    }
}
