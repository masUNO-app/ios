import Foundation

/// The custom keys `send-push` puts next to `aps` (NOTIF §5.5). Both the app and the extension decode it.
nonisolated struct NotificationPayload: Codable, Sendable {
    var kind: String
    var gameID: UUID?
    var outboxID: Int64?
    var game: GameInfo?
    var sender: Sender?
    var others: [Person]
    var body: String?
    var count: Int?
    var place: PlacePin?

    init(
        kind: String, gameID: UUID? = nil, outboxID: Int64? = nil, game: GameInfo? = nil,
        sender: Sender? = nil, others: [Person] = [], body: String? = nil, count: Int? = nil,
        place: PlacePin? = nil
    ) {
        self.kind = kind
        self.gameID = gameID
        self.outboxID = outboxID
        self.game = game
        self.sender = sender
        self.others = others
        self.body = body
        self.count = count
        self.place = place
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        gameID = try container.decodeIfPresent(UUID.self, forKey: .gameID)
        outboxID = try container.decodeIfPresent(Int64.self, forKey: .outboxID)
        game = try container.decodeIfPresent(GameInfo.self, forKey: .game)
        sender = try container.decodeIfPresent(Sender.self, forKey: .sender)
        others = try container.decodeIfPresent([Person].self, forKey: .others) ?? []
        body = try container.decodeIfPresent(String.self, forKey: .body)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        place = try container.decodeIfPresent(PlacePin.self, forKey: .place)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(gameID, forKey: .gameID)
        try container.encodeIfPresent(outboxID, forKey: .outboxID)
        try container.encodeIfPresent(game, forKey: .game)
        try container.encodeIfPresent(sender, forKey: .sender)
        if !others.isEmpty { try container.encode(others, forKey: .others) }
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(place, forKey: .place)
    }

    nonisolated struct GameInfo: Codable, Sendable {
        var title: String
        var sport: String
    }

    nonisolated struct Sender: Codable, Sendable {
        var id: UUID
        var name: String
        var initials: String
    }

    nonisolated struct Person: Codable, Sendable {
        var id: UUID
        var name: String
    }

    nonisolated struct PlacePin: Codable, Sendable {
        var name: String
        var lat: Double
        var lng: Double
    }

    enum CodingKeys: String, CodingKey {
        case kind, game, sender, others, body, count, place
        case gameID = "game_id"
        case outboxID = "outbox_id"
    }

    /// Reads a notification's `userInfo`. Nil when it isn't one of ours.
    init?(userInfo: [AnyHashable: Any]) {
        let object = userInfo.reduce(into: [String: Any]()) { result, item in
            guard let key = item.key as? String, key != "aps" else { return }
            result[key] = item.value
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(NotificationPayload.self, from: data)
        else { return nil }
        self = decoded
    }

    /// iOS supplies the sender in the communication header. Keep names in the plain
    /// APNs fallback only, including summaries sent by older server versions.
    func communicationBody(fallback: String) -> String {
        let text = body ?? fallback
        if (count ?? 1) > 1, let separator = text.range(of: " · ", options: .backwards) {
            return String(text[separator.upperBound...])
        }
        if body == nil, let sender, text.hasPrefix("\(sender.name): ") {
            return String(text.dropFirst(sender.name.count + 2))
        }
        return text
    }

    /// Where a tap goes. Signup opens the app as it is. Win-back opens the map.
    /// - Returns: A `masuno` URL, or nil when the tap should only bring the app forward.
    func routeURL() -> URL? {
        switch kind {
        case "signup_approved":
            return nil
        case "winback":
            return URL(string: "masuno://map")
        case "chat_message":
            guard let gameID else { return nil }
            return URL(string: "masuno://game/\(gameID.uuidString)/chat")
        default:
            guard let gameID else { return nil }
            return URL(string: "masuno://game/\(gameID.uuidString)")
        }
    }
}
