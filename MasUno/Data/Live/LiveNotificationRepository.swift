import Foundation
import Supabase

/// The live `NotificationRepository`: device tokens, preferences, chat mute and opened receipts.
final class LiveNotificationRepository: NotificationRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func registerDevice(token: String, environment: String, locale: String, appVersion: String) async throws {
        try await liveRequest {
            try await client.rpc(
                "register_device",
                params: RegisterDeviceParams(token: token, environment: environment, locale: locale, appVersion: appVersion)
            ).execute()
        }
    }

    func unregisterDevice(token: String) async throws {
        try await liveRequest {
            try await client.rpc("unregister_device", params: UnregisterDeviceParams(token: token)).execute()
        }
    }

    func fetchPrefs() async throws -> NotificationPrefs {
        try await liveRequest {
            let rows: [NotificationPrefs] = try await client.from("notification_prefs").select().execute().value
            return rows.first ?? .standard
        }
    }

    func setPrefs(_ prefs: NotificationPrefs) async throws {
        _ = try await liveRequest {
            let rows: [NotificationPrefs] = try await client.rpc(
                "set_notification_prefs", params: PrefsParams(prefs)
            ).execute().value
            return rows.first ?? prefs
        }
    }

    func setChatMuted(gameID: UUID, muted: Bool) async throws {
        try await liveRequest {
            try await client.rpc(
                "set_chat_muted", params: ChatMutedParams(gameID: gameID, muted: muted)
            ).execute()
        }
    }

    func markOpened(_ outboxID: Int64) async throws {
        try await liveRequest {
            try await client.rpc("notification_opened", params: OpenedParams(outboxID: outboxID)).execute()
        }
    }
}

nonisolated private struct RegisterDeviceParams: Encodable, Sendable {
    let token: String
    let environment: String
    let locale: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case environment = "p_environment"
        case locale = "p_locale"
        case appVersion = "p_app_version"
    }
}

nonisolated private struct UnregisterDeviceParams: Encodable, Sendable {
    let token: String
    enum CodingKeys: String, CodingKey { case token = "p_token" }
}

nonisolated private struct ChatMutedParams: Encodable, Sendable {
    let gameID: UUID
    let muted: Bool
    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case muted = "p_muted"
    }
}

nonisolated private struct OpenedParams: Encodable, Sendable {
    let outboxID: Int64
    enum CodingKeys: String, CodingKey { case outboxID = "p_outbox_id" }
}

/// `set_notification_prefs` takes each flag as its own `p_` argument.
nonisolated private struct PrefsParams: Encodable, Sendable {
    let prefs: NotificationPrefs

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prefs.interestMatch, forKey: .interestMatch)
        try container.encode(prefs.spotOpen, forKey: .spotOpen)
        try container.encode(prefs.reminders, forKey: .reminders)
        try container.encode(prefs.hosting, forKey: .hosting)
        try container.encode(prefs.chat, forKey: .chat)
        try container.encode(prefs.winback, forKey: .winback)
    }

    enum CodingKeys: String, CodingKey {
        case interestMatch = "p_interest_match"
        case spotOpen = "p_spot_open"
        case reminders = "p_reminders"
        case hosting = "p_hosting"
        case chat = "p_chat"
        case winback = "p_winback"
    }
}
