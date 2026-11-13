import Foundation

// What the backend sends and takes for sign-in and reference data (`docs/API.md`). None of this
// imports Supabase, so `ContractTests` can check it without a server.

/// A row in `university_lookup`.
nonisolated struct UniversityRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let shortName: String
    let emailDomain: String
    let ssoProvider: String?
    let signupEnabled: Bool
    let centerLat: Double
    let centerLng: Double

    enum CodingKeys: String, CodingKey {
        case id, name
        case shortName = "short_name"
        case emailDomain = "email_domain"
        case ssoProvider = "sso_provider"
        case signupEnabled = "signup_enabled"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
    }

    /// `nil` for a provider this build doesn't know: nobody could sign in there with it.
    var university: University? {
        guard let provider = ssoProvider.flatMap(SSOProvider.init(rawValue:)) else { return nil }
        return University(
            id: id, name: name, shortName: shortName, emailDomain: emailDomain,
            centerLatitude: centerLat, centerLongitude: centerLng,
            ssoProvider: provider, signupEnabled: signupEnabled
        )
    }
}

/// A row in `app_config`. Values are strings, or a boolean switch like `chat_enabled`; anything else is skipped.
nonisolated struct AppConfigRow: Decodable, Sendable {
    let key: String
    let value: String?
    let flag: Bool?

    enum CodingKeys: String, CodingKey { case key, value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try? container.decode(String.self, forKey: .value)
        flag = try? container.decode(Bool.self, forKey: .value)
    }
}

extension AppConfig {
    /// The fallback, with whatever the server sent on top.
    init(rows: [AppConfigRow]) {
        self = .fallback
        for row in rows {
            if row.key == "chat_enabled" { chatEnabled = row.flag ?? false }
            guard let value = row.value else { continue }
            switch row.key {
            case "min_supported_version": minSupportedVersion = value
            case "support_email": supportEmail = value
            case "privacy_url": if let url = URL(string: value) { privacyURL = url }
            default: break
            }
        }
    }
}

/// A row in `activities`.
nonisolated struct ActivityRow: Decodable, Sendable {
    let slug: String
    let kind: String
    let labelEN: String
    let labelES: String
    let emoji: String
    let sortOrder: Int
    let postable: Bool
    let interestSelectable: Bool
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case slug, kind, emoji, postable, active
        case labelEN = "label_en"
        case labelES = "label_es"
        case sortOrder = "sort_order"
        case interestSelectable = "interest_selectable"
    }

    var activity: Activity {
        Activity(
            slug: slug, kind: kind, labelEN: labelEN, labelES: labelES, emoji: emoji, sortOrder: sortOrder,
            postable: postable, interestSelectable: interestSelectable, active: active
        )
    }
}

/// The part of `my_profile` that decides the next step after sign-in. Timestamps stay strings:
/// only whether they're set matters here.
nonisolated struct ProfileStatusRow: Decodable, Sendable {
    let guidelinesAcceptedAt: String?
    let bannedAt: String?

    enum CodingKeys: String, CodingKey {
        case guidelinesAcceptedAt = "guidelines_accepted_at"
        case bannedAt = "banned_at"
    }
}

extension AuthState {
    /// `row` is nil until `complete_profile` has run, which an account can't do while it waits
    /// for approval (`signup_status`). A ban comes first, so a banned account never lands on a
    /// step it can't finish.
    init(profile row: ProfileStatusRow?, isPending: Bool = false, userID: UUID) {
        guard let row else {
            self = isPending ? .pendingApproval : .needsProfile
            return
        }
        if row.bannedAt != nil {
            self = .suspended
        } else if row.guidelinesAcceptedAt == nil {
            self = .needsGuidelines
        } else {
            self = .signedIn(userID: userID)
        }
    }
}

/// The parameters of `complete_profile`.
nonisolated struct CompleteProfileParams: Encodable, Sendable {
    let firstName: String
    let lastName: String
    let gradYear: Int
    let interests: [String]
    let locale: String

    enum CodingKeys: String, CodingKey {
        case firstName = "p_first_name"
        case lastName = "p_last_name"
        case gradYear = "p_grad_year"
        case interests = "p_interests"
        case locale = "p_locale"
    }

    init(_ input: ProfileInput) {
        firstName = input.firstName
        lastName = input.lastName
        gradYear = input.gradYear
        interests = input.interests.map(\.slug)
        locale = input.locale
    }
}

/// What a failed school sign-in sends back in the callback URL (`docs/API.md`, Auth errors).
nonisolated struct SignInFailure: Hashable, Sendable {
    var error: String?
    var code: String?
    var message: String?

    var domainError: DomainError {
        let parts = [error, code, message].compactMap { $0?.lowercased() }
        if parts.contains(where: { $0.contains("email_not_allowed") }) { return .emailNotAllowed }
        // Entra's "needs admin approval" errors, and the way back out of its approval page.
        let consent = ["access_denied", "consent_required", "aadsts65001", "aadsts90094"]
        if parts.contains(where: { part in consent.contains { part.contains($0) } }) { return .schoolApprovalNeeded }
        return .signInFailed
    }
}

// MARK: - Games, profiles and safety (B7)

/// Postgres `timestamptz` as PostgREST sends it: ISO 8601 with up to microseconds and an offset.
/// Rows parse it themselves, so they decode the same with any `JSONDecoder`.
nonisolated enum ServerTime {
    static func date(from text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    /// What RPC parameters and filters send: UTC with milliseconds.
    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

nonisolated extension KeyedDecodingContainer {
    func decodeServerTime(forKey key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let date = ServerTime.date(from: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a timestamp: \(text)")
        }
        return date
    }

    func decodeServerTimeIfPresent(forKey key: Key) throws -> Date? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ServerTime.date(from: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a timestamp: \(text)")
        }
        return date
    }
}

/// A row in `game_cards`, also what every game RPC returns.
nonisolated struct GameCardRow: Decodable, Sendable {
    let id: UUID
    let hostID: UUID
    let hostFirstName: String
    let hostLastInitial: String
    let hostGradYear: Int
    let activitySlug: String
    let title: String
    let startsAt: Date
    let durationMinutes: Int
    let endsAt: Date
    let capacity: Int
    let goingCount: Int
    let notes: String?
    let placeName: String
    let placeAddress: String
    let lat: Double
    let lng: Double
    let meetPoint: String?
    let materialChangeAt: Date?
    let cancelledAt: Date?
    let autoRepost: Bool
    let repostedAt: Date?
    let createdAt: Date
    let myRole: String?
    let myJoinedAt: Date?
    let hasBlockedAttendee: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, capacity, notes, lat, lng
        case hostID = "host_id"
        case hostFirstName = "host_first_name"
        case hostLastInitial = "host_last_initial"
        case hostGradYear = "host_grad_year"
        case activitySlug = "activity_slug"
        case startsAt = "starts_at"
        case durationMinutes = "duration_minutes"
        case endsAt = "ends_at"
        case goingCount = "going_count"
        case placeName = "place_name"
        case placeAddress = "place_address"
        case meetPoint = "meet_point"
        case materialChangeAt = "material_change_at"
        case cancelledAt = "cancelled_at"
        case autoRepost = "auto_repost"
        case repostedAt = "reposted_at"
        case createdAt = "created_at"
        case myRole = "my_role"
        case myJoinedAt = "my_joined_at"
        case hasBlockedAttendee = "has_blocked_attendee"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        hostID = try c.decode(UUID.self, forKey: .hostID)
        hostFirstName = try c.decode(String.self, forKey: .hostFirstName)
        hostLastInitial = try c.decodeIfPresent(String.self, forKey: .hostLastInitial) ?? ""
        hostGradYear = try c.decode(Int.self, forKey: .hostGradYear)
        activitySlug = try c.decode(String.self, forKey: .activitySlug)
        title = try c.decode(String.self, forKey: .title)
        startsAt = try c.decodeServerTime(forKey: .startsAt)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        endsAt = try c.decodeServerTime(forKey: .endsAt)
        capacity = try c.decode(Int.self, forKey: .capacity)
        goingCount = try c.decode(Int.self, forKey: .goingCount)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        placeName = try c.decode(String.self, forKey: .placeName)
        placeAddress = try c.decode(String.self, forKey: .placeAddress)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        meetPoint = try c.decodeIfPresent(String.self, forKey: .meetPoint)
        materialChangeAt = try c.decodeServerTimeIfPresent(forKey: .materialChangeAt)
        cancelledAt = try c.decodeServerTimeIfPresent(forKey: .cancelledAt)
        autoRepost = try c.decode(Bool.self, forKey: .autoRepost)
        repostedAt = try c.decodeServerTimeIfPresent(forKey: .repostedAt)
        createdAt = try c.decodeServerTime(forKey: .createdAt)
        myRole = try c.decodeIfPresent(String.self, forKey: .myRole)
        myJoinedAt = try c.decodeServerTimeIfPresent(forKey: .myJoinedAt)
        hasBlockedAttendee = try c.decodeIfPresent(Bool.self, forKey: .hasBlockedAttendee) ?? false
    }

    func game(activity: (String) -> Activity) -> Game {
        Game(
            id: id,
            host: PersonSummary(id: hostID, firstName: hostFirstName, lastInitial: hostLastInitial, gradYear: hostGradYear),
            activity: activity(activitySlug), title: title, startsAt: startsAt,
            durationMinutes: durationMinutes, endsAt: endsAt, capacity: capacity, goingCount: goingCount,
            notes: notes, place: Place(name: placeName, address: placeAddress, latitude: lat, longitude: lng),
            meetPoint: meetPoint, materialChangeAt: materialChangeAt, cancelledAt: cancelledAt,
            autoRepost: autoRepost, repostedAt: repostedAt, createdAt: createdAt,
            myRole: myRole.flatMap(GameRole.init(rawValue:)), myJoinedAt: myJoinedAt,
            hasBlockedAttendee: hasBlockedAttendee
        )
    }
}

/// A row from `guest_games(p_university)`: a `game_cards` row without names, notes, the meet-up
/// spot or anything per viewer, since a guest has no account.
nonisolated struct GuestGameRow: Decodable, Sendable {
    let id: UUID
    let activitySlug: String
    let title: String
    let startsAt: Date
    let durationMinutes: Int
    let endsAt: Date
    let capacity: Int
    let goingCount: Int
    let placeName: String
    let placeAddress: String
    let lat: Double
    let lng: Double
    let repostedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, capacity, lat, lng
        case activitySlug = "activity_slug"
        case startsAt = "starts_at"
        case durationMinutes = "duration_minutes"
        case endsAt = "ends_at"
        case goingCount = "going_count"
        case placeName = "place_name"
        case placeAddress = "place_address"
        case repostedAt = "reposted_at"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        activitySlug = try c.decode(String.self, forKey: .activitySlug)
        title = try c.decode(String.self, forKey: .title)
        startsAt = try c.decodeServerTime(forKey: .startsAt)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        endsAt = try c.decodeServerTime(forKey: .endsAt)
        capacity = try c.decode(Int.self, forKey: .capacity)
        goingCount = try c.decode(Int.self, forKey: .goingCount)
        placeName = try c.decode(String.self, forKey: .placeName)
        placeAddress = try c.decode(String.self, forKey: .placeAddress)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        repostedAt = try c.decodeServerTimeIfPresent(forKey: .repostedAt)
        createdAt = try c.decodeServerTime(forKey: .createdAt)
    }

    /// The host is `PersonSummary.hidden`, which is how screens know to leave people out.
    func game(activity: (String) -> Activity) -> Game {
        Game(
            id: id, host: .hidden, activity: activity(activitySlug), title: title, startsAt: startsAt,
            durationMinutes: durationMinutes, endsAt: endsAt, capacity: capacity, goingCount: goingCount,
            notes: nil, place: Place(name: placeName, address: placeAddress, latitude: lat, longitude: lng),
            meetPoint: nil, materialChangeAt: nil, cancelledAt: nil,
            autoRepost: false, repostedAt: repostedAt, createdAt: createdAt,
            myRole: nil, myJoinedAt: nil, hasBlockedAttendee: false
        )
    }
}

/// A row in `game_attendees`.
nonisolated struct AttendeeRow: Decodable, Sendable {
    let userID: UUID
    let firstName: String
    let lastInitial: String
    let gradYear: Int
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case userID = "user_id"
        case firstName = "first_name"
        case lastInitial = "last_initial"
        case gradYear = "grad_year"
        case joinedAt = "joined_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastInitial = try c.decodeIfPresent(String.self, forKey: .lastInitial) ?? ""
        gradYear = try c.decode(Int.self, forKey: .gradYear)
        role = try c.decode(String.self, forKey: .role)
        joinedAt = try c.decodeServerTime(forKey: .joinedAt)
    }

    var attendee: Attendee {
        Attendee(
            person: PersonSummary(id: userID, firstName: firstName, lastInitial: lastInitial, gradYear: gradYear),
            role: GameRole(rawValue: role) ?? .player, joinedAt: joinedAt
        )
    }
}

/// A row in `game_activity`. The actor columns are null for a deleted account or a blocked pair.
nonisolated struct GameActivityRow: Decodable, Sendable {
    let id: UUID
    let eventID: UUID
    let kind: String
    let actorID: UUID?
    let actorFirstName: String?
    let actorLastInitial: String?
    let actorGradYear: Int?
    let at: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, at
        case eventID = "event_id"
        case actorID = "actor_id"
        case actorFirstName = "actor_first_name"
        case actorLastInitial = "actor_last_initial"
        case actorGradYear = "actor_grad_year"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        kind = try c.decode(String.self, forKey: .kind)
        actorID = try c.decodeIfPresent(UUID.self, forKey: .actorID)
        actorFirstName = try c.decodeIfPresent(String.self, forKey: .actorFirstName)
        actorLastInitial = try c.decodeIfPresent(String.self, forKey: .actorLastInitial)
        actorGradYear = try c.decodeIfPresent(Int.self, forKey: .actorGradYear)
        at = try c.decodeServerTime(forKey: .at)
    }

    /// `nil` for a kind this build doesn't know, so an older app skips it instead of failing.
    var entry: GameActivityEntry? {
        guard let kind = GameActivityEntry.Kind(rawValue: kind) else { return nil }
        var actor: PersonSummary?
        if let actorID, let actorFirstName, let actorGradYear {
            actor = PersonSummary(id: actorID, firstName: actorFirstName, lastInitial: actorLastInitial ?? "", gradYear: actorGradYear)
        }
        return GameActivityEntry(id: id, gameID: eventID, kind: kind, actor: actor, at: at)
    }
}

/// A row in `my_profile`, also what `complete_profile` returns.
nonisolated struct MyProfileRow: Decodable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let gradYear: Int
    let universityID: UUID
    let universityName: String
    let universityShortName: String
    let universityEmailDomain: String
    let centerLat: Double
    let centerLng: Double
    let interests: [String]
    let chatRulesAcceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, interests
        case chatRulesAcceptedAt = "chat_rules_accepted_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case gradYear = "grad_year"
        case universityID = "university_id"
        case universityName = "university_name"
        case universityShortName = "university_short_name"
        case universityEmailDomain = "university_email_domain"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastName = try c.decode(String.self, forKey: .lastName)
        gradYear = try c.decode(Int.self, forKey: .gradYear)
        universityID = try c.decode(UUID.self, forKey: .universityID)
        universityName = try c.decode(String.self, forKey: .universityName)
        universityShortName = try c.decode(String.self, forKey: .universityShortName)
        universityEmailDomain = try c.decode(String.self, forKey: .universityEmailDomain)
        centerLat = try c.decode(Double.self, forKey: .centerLat)
        centerLng = try c.decode(Double.self, forKey: .centerLng)
        interests = try c.decodeIfPresent([String].self, forKey: .interests) ?? []
        // Missing on a server without chat.
        chatRulesAcceptedAt = try c.decodeServerTimeIfPresent(forKey: .chatRulesAcceptedAt)
    }

    /// `my_profile` doesn't carry the campus's sign-in provider; the map and Me card don't need it.
    func profile(activity: (String) -> Activity) -> Profile {
        Profile(
            id: id, firstName: firstName, lastName: lastName, gradYear: gradYear,
            university: University(
                id: universityID, name: universityName, shortName: universityShortName,
                emailDomain: universityEmailDomain, centerLatitude: centerLat, centerLongitude: centerLng
            ),
            interests: interests.map(activity), chatRulesAcceptedAt: chatRulesAcceptedAt
        )
    }
}

/// A row from `my_blocks()`.
nonisolated struct BlockedPersonRow: Decodable, Sendable {
    let userID: UUID
    let firstName: String
    let lastInitial: String?
    let gradYear: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case firstName = "first_name"
        case lastInitial = "last_initial"
        case gradYear = "grad_year"
    }

    var person: PersonSummary {
        PersonSummary(id: userID, firstName: firstName, lastInitial: lastInitial ?? "", gradYear: gradYear)
    }
}

/// Trimmed, and `nil` rather than "" (`docs/API.md`, Conventions).
nonisolated func optionalText(_ text: String?) -> String? {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

/// The parameters of `create_game`, plus `p_id` for `update_game`. PostgREST finds a function by
/// its argument names, so every one is sent, with an explicit null when it's empty.
nonisolated struct GameDraftParams: Encodable, Sendable {
    let id: UUID?
    let draft: GameDraft

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case activitySlug = "p_activity_slug"
        case title = "p_title"
        case startsAt = "p_starts_at"
        case durationMinutes = "p_duration_minutes"
        case capacity = "p_capacity"
        case notes = "p_notes"
        case placeName = "p_place_name"
        case placeAddress = "p_place_address"
        case lat = "p_lat"
        case lng = "p_lng"
        case meetPoint = "p_meet_point"
        case autoRepost = "p_auto_repost"
    }

    init(id: UUID? = nil, _ draft: GameDraft) {
        self.id = id
        self.draft = draft
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let id { try c.encode(id, forKey: .id) }
        try c.encode(draft.activity.slug, forKey: .activitySlug)
        try c.encode(draft.title.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .title)
        try c.encode(ServerTime.string(from: draft.startsAt), forKey: .startsAt)
        try c.encode(draft.durationMinutes, forKey: .durationMinutes)
        try c.encode(draft.capacity, forKey: .capacity)
        try c.encode(optionalText(draft.notes), forKey: .notes)
        try c.encode(draft.place.name, forKey: .placeName)
        try c.encode(draft.place.address, forKey: .placeAddress)
        try c.encode(draft.place.latitude, forKey: .lat)
        try c.encode(draft.place.longitude, forKey: .lng)
        try c.encode(optionalText(draft.meetPoint), forKey: .meetPoint)
        try c.encode(draft.autoRepost, forKey: .autoRepost)
    }
}

/// `p_id` for `cancel_game`, `join_game` and `leave_game`.
nonisolated struct GameIDParams: Encodable, Sendable {
    let id: UUID
    enum CodingKeys: String, CodingKey { case id = "p_id" }
}

/// `p_university` for `guest_games`.
nonisolated struct GuestGamesParams: Encodable, Sendable {
    let campus: UUID
    enum CodingKeys: String, CodingKey { case campus = "p_university" }
}

/// `p_user_id` for `block` and `unblock`.
nonisolated struct UserIDParams: Encodable, Sendable {
    let userID: UUID
    enum CodingKeys: String, CodingKey { case userID = "p_user_id" }
}

/// The parameters of `report`: exactly one of the two IDs, the other sent as null. A message goes to
/// `report_message` instead, with `p_message_id`.
nonisolated struct ReportParams: Encodable, Sendable {
    let target: ReportTarget
    let reason: ReportReason
    let note: String?

    enum CodingKeys: String, CodingKey {
        case userID = "p_user_id"
        case gameID = "p_game_id"
        case messageID = "p_message_id"
        case reason = "p_reason"
        case note = "p_note"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch target {
        case .person(let id):
            try c.encode(id, forKey: .userID)
            try c.encodeNil(forKey: .gameID)
        case .game(let id):
            try c.encodeNil(forKey: .userID)
            try c.encode(id, forKey: .gameID)
        case .message(let id):
            try c.encode(id, forKey: .messageID)
        }
        try c.encode(reason.rawValue, forKey: .reason)
        try c.encode(optionalText(note), forKey: .note)
    }
}

// MARK: - Group chat (B20, E26)

/// A row in `game_messages`, also what `send_message` returns.
nonisolated struct GameMessageRow: Decodable, Sendable {
    let id: UUID
    let eventID: UUID
    let senderID: UUID
    let senderFirstName: String
    let senderLastInitial: String
    let senderGradYear: Int
    let body: String
    let clientID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case eventID = "event_id"
        case senderID = "sender_id"
        case senderFirstName = "sender_first_name"
        case senderLastInitial = "sender_last_initial"
        case senderGradYear = "sender_grad_year"
        case clientID = "client_id"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        senderID = try c.decode(UUID.self, forKey: .senderID)
        senderFirstName = try c.decode(String.self, forKey: .senderFirstName)
        senderLastInitial = try c.decodeIfPresent(String.self, forKey: .senderLastInitial) ?? ""
        senderGradYear = try c.decode(Int.self, forKey: .senderGradYear)
        body = try c.decode(String.self, forKey: .body)
        clientID = try c.decode(UUID.self, forKey: .clientID)
        createdAt = try c.decodeServerTime(forKey: .createdAt)
    }

    var message: ChatMessage {
        ChatMessage(
            id: id, gameID: eventID,
            sender: PersonSummary(id: senderID, firstName: senderFirstName, lastInitial: senderLastInitial, gradYear: senderGradYear),
            body: body, clientID: clientID, createdAt: createdAt
        )
    }
}

/// A row in `chat_unread`: a game with messages you haven't seen.
nonisolated struct ChatUnreadRow: Decodable, Sendable {
    let eventID: UUID
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case unreadCount = "unread_count"
    }
}

/// The parameters of `send_message`.
nonisolated struct SendMessageParams: Encodable, Sendable {
    let gameID: UUID
    let body: String
    let clientID: UUID

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case body = "p_body"
        case clientID = "p_client_id"
    }
}

/// `p_game_id` for `mark_chat_read`.
nonisolated struct ChatGameParams: Encodable, Sendable {
    let gameID: UUID
    enum CodingKeys: String, CodingKey { case gameID = "p_game_id" }
}

/// The name of a game's private Realtime channel. Postgres writes UUIDs in lowercase, and the
/// channel policy compares the whole name.
nonisolated func chatChannelName(gameID: UUID) -> String {
    "game:\(gameID.uuidString.lowercased()):chat"
}

/// Must match the topic in `20261112000000_games_realtime`, which only lets the campus's people listen.
nonisolated func gamesChannelName(campus: UUID) -> String {
    "campus:\(campus.uuidString.lowercased()):games"
}
