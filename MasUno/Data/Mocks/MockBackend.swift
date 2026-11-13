#if DEBUG
import Foundation
import Observation

/// One in-memory backend behind every protocol, for previews and tests. It enforces the
/// same rules and raises the same codes as the RPCs in `docs/API.md`, so code written
/// against it behaves the same on `masuno-dev`. Compiled out of Release (N27).
@Observable
final class MockBackend: AuthService, GameRepository, ProfileRepository, SafetyRepository, ChatRepository, AppConfigRepository {
    private(set) var state: AuthState
    private(set) var games: [Game]
    private(set) var reports: [(target: ReportTarget, reason: ReportReason, note: String?)] = []
    private(set) var profile: Profile?

    /// Thrown by the next call instead of running it: offline, a server error, a lost race.
    var nextError: DomainError?
    /// Delay on every call, to see loading states in previews.
    var latency: Duration = .zero
    /// The clock the rules use. Tests set this to step past a game's end.
    var now: Date
    /// `university_lookup`. Change this to launch somewhere else, or set `signupEnabled` to close a campus.
    var universities = [MockFixtures.tec]
    /// The account the next school sign-in comes back with, whichever school was picked.
    /// By default it's a student at the school picked.
    var schoolAccountEmail: String?
    /// The next school sign-in closes the web sheet instead of signing in.
    var cancelsNextSignIn = false
    /// `-raceJoin YES`: the next join waits a second, then loses the last spot to someone else.
    var losesNextJoinRace = false
    /// `app_config.chat_enabled`. Off, `sendMessage` answers `chat_disabled`.
    var chatEnabled = true

    let me: PersonSummary
    private var attendees: [UUID: [Attendee]]
    private var activity: [UUID: [GameActivityEntry]] = [:]
    private var people: [UUID: PersonSummary]
    private var blockedIDs: [UUID] = []
    private var messages: [UUID: [ChatMessage]]
    private var lastRead: [UUID: Date] = [:]
    private var listeners: [UUID: [UUID: AsyncStream<ChatUpdate>.Continuation]] = [:]
    private var gameChangeListeners: [UUID: AsyncStream<GameChanges>.Continuation] = [:]
    private var isSuspended = false
    /// The campus the account signing in belongs to.
    private var signInCampus = MockFixtures.tec
    /// Accounts made with `signUp`: email → password.
    private var passwords: [String: String] = [:]
    /// Signed up and nobody has run `approveSignUp()` yet.
    private var isAwaitingApproval = false

    /// `state` defaults to signed in with the Monterrey fixtures. Pass `.signedOut(expired: false)`
    /// to preview onboarding: the new account then has no profile until `completeProfile`.
    init(state: AuthState? = nil, now: Date = .now) {
        let world = MockFixtures.world(now: now)
        self.now = now
        self.me = world.me.summary
        self.games = world.games
        self.attendees = world.attendees
        self.activity = Dictionary(uniqueKeysWithValues: world.attendees.map { gameID, roster in
            (gameID, roster.enumerated().map { index, attendee in
                GameActivityEntry(id: UUID(), gameID: gameID, kind: index == 0 ? .created : .joined, actor: attendee.person, at: attendee.joinedAt)
            })
        })
        self.people = world.people
        self.messages = world.messages
        self.state = state ?? .signedIn(userID: world.me.id)
        self.profile = state == nil ? world.me : nil
    }

    // MARK: Test and preview controls

    /// Another player takes spots, as if they'd joined from their own phone.
    func fillGame(id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        games[index].goingCount = games[index].capacity
    }

    /// Another player leaves, firing auto-repost if the game was full.
    /// When the roster matches the count, that player comes off Who's going too.
    func simulateDropOut(id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let game = games[index]
        guard game.goingCount > 1 else { return }
        if attendees[id]?.count == game.goingCount,
           let leaving = attendees[id]?.last(where: { $0.role != .host }) {
            attendees[id]?.removeAll { $0.id == leaving.id }
        }
        games[index].goingCount -= 1
        if game.isFull, game.autoRepost, !game.isCancelled { games[index].repostedAt = now }
    }

    /// The host of a game you're in cancels it, from their own phone.
    func cancelAsHost(id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        games[index].cancelledAt = now
        log(.cancelled, id, actor: games[index].host)
    }

    /// Someone else in the game posts from their own phone, and the chat channel says so.
    @discardableResult
    func receiveMessage(from sender: PersonSummary, in gameID: UUID, body: String) -> ChatMessage {
        let message = ChatMessage(id: UUID(), gameID: gameID, sender: sender, body: body, clientID: UUID(), createdAt: now)
        messages[gameID, default: []].append(message)
        announce(.message, in: gameID)
        return message
    }

    /// The account hasn't agreed to "Before you chat" yet.
    func resetChatRules() {
        profile?.chatRulesAcceptedAt = nil
    }

    /// A moderator sets `banned_at`.
    func suspend() {
        isSuspended = true
        state = .suspended
    }

    /// Someone on the team runs `private.approve_signup`. The app finds out on its next `refreshStatus()`.
    func approveSignUp() {
        isAwaitingApproval = false
    }

    /// The session ended: on purpose, or `expired` if the saved session stopped working.
    func endSession(expired: Bool) {
        state = .signedOut(expired: expired)
    }

    // MARK: AuthService

    var suggestedName: SuggestedName? {
        state == .needsProfile ? SuggestedName(first: "Emilio", last: "Garza") : nil
    }

    func restoreSession() async {
        if state == .loading { state = .signedOut(expired: false) }
    }

    /// Debug has no web sheet. Like the auth hook, this checks the account, not the school picked,
    /// and only for a new account: the hook doesn't run for an existing one.
    func signIn(at school: University) async throws {
        try await begin()
        if cancelsNextSignIn {
            cancelsNextSignIn = false
            return
        }
        if profile == nil {
            let email = schoolAccountEmail ?? "a01234567@\(school.emailDomain)"
            guard let campus = campus(for: email, in: universities), campus.signupEnabled else {
                throw DomainError.emailNotAllowed
            }
            signInCampus = campus
        }
        state = profile == nil ? .needsProfile : .signedIn(userID: me.id)
    }

    /// Like the auth hook: a school address at an open campus gets in and waits for approval.
    func signUp(email: String, password: String) async throws {
        try await begin()
        let email = email.lowercased()
        guard let campus = campus(for: email, in: universities), campus.signupEnabled else {
            throw DomainError.emailNotAllowed
        }
        guard passwords[email] == nil else { throw DomainError.emailTaken }
        passwords[email] = password
        signInCampus = campus
        profile = nil
        isAwaitingApproval = true
        state = .pendingApproval
    }

    func refreshStatus() async throws {
        try await begin()
        if state == .pendingApproval, !isAwaitingApproval { state = .needsProfile }
    }

    func signIn(email: String, password: String) async throws {
        try await begin()
        if let saved = passwords[email.lowercased()], saved == password {
            if isAwaitingApproval {
                state = .pendingApproval
            } else {
                state = profile == nil ? .needsProfile : .signedIn(userID: me.id)
            }
            return
        }
        guard email.lowercased() == MockFixtures.reviewEmail, password == MockFixtures.reviewPassword else {
            throw DomainError.invalidCredentials
        }
        var review = MockFixtures.world(now: now).me
        review.university = MockFixtures.demoCampus
        profile = review
        state = .signedIn(userID: me.id)
    }

    func completeProfile(_ input: ProfileInput) async throws {
        try await begin()
        if isAwaitingApproval { throw DomainError.pendingApproval }
        profile = try validated(input)
        state = .needsGuidelines
    }

    func acceptGuidelines() async throws {
        try await begin()
        state = .signedIn(userID: me.id)
    }

    func signOut() async throws {
        try await begin()
        state = .signedOut(expired: false)
    }

    /// Like `delete-account` (B9): frees the spots in upcoming joined games, then deletes every game
    /// you host, so they're gone for everyone rather than cancelled.
    func deleteAccount() async throws {
        try await begin()
        for game in games where game.myRole == .player && !game.hasEnded(now: now) {
            _ = try await leaveGame(id: game.id)
        }
        let hosted = Set(games.filter { $0.host.id == me.id }.map(\.id))
        games.removeAll { hosted.contains($0.id) }
        for id in hosted {
            attendees[id] = nil
            activity[id] = nil
            messages[id] = nil
        }
        for id in messages.keys { messages[id]?.removeAll { $0.sender.id == me.id } }
        profile = nil
        state = .signedOut(expired: false)
    }

    // MARK: GameRepository

    func fetchMapGames() async throws -> [Game] {
        try await begin()
        return onTheMap(visibleGames)
    }

    /// Like `guest_games`: the map for someone with no blocks, stripped of names, notes and the
    /// meet-up spot. A read, so it works signed out. The mock has one campus, so any open campus in
    /// `universities` gets its games; a closed one, an unlisted one or the demo campus gets none.
    func fetchGuestGames(campus: UUID) async throws -> [Game] {
        try await begin()
        guard campus != MockFixtures.demoCampus.id,
              universities.contains(where: { $0.id == campus && $0.signupEnabled })
        else { return [] }
        return onTheMap(games).map(Self.asGuest)
    }

    func fetchMyGames() async throws -> [Game] {
        try await begin()
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        return visibleGames.filter { $0.myRole != nil && $0.endsAt > cutoff }
    }

    func fetchGame(id: UUID) async throws -> Game {
        try await begin()
        return try visibleGame(id)
    }

    func fetchGames(ids: [UUID]) async throws -> [Game] {
        try await begin()
        return visibleGames.filter { ids.contains($0.id) }
    }

    func fetchAttendees(gameID: UUID) async throws -> [Attendee] {
        try await begin()
        _ = try visibleGame(gameID)
        return (attendees[gameID] ?? [])
            .filter { !blockedIDs.contains($0.id) }
            .sorted { ($0.role == .host ? 0 : 1, $0.joinedAt) < ($1.role == .host ? 0 : 1, $1.joinedAt) }
    }

    func fetchActivity(gameID: UUID) async throws -> [GameActivityEntry] {
        try await begin()
        _ = try visibleGame(gameID)
        return (activity[gameID] ?? []).filter { entry in
            !(entry.actor.map { blockedIDs.contains($0.id) } ?? false)
        }
    }

    func createGame(_ draft: GameDraft) async throws -> Game {
        try await beginWrite()
        try validate(draft, checksTime: true)
        let hosted = games.filter { $0.myRole == .host && !$0.isCancelled && !$0.hasEnded(now: now) }
        guard hosted.count < GameDraft.maxUpcomingHosted else { throw DomainError.limitReached }

        var game = Game(
            id: UUID(), host: me, activity: draft.activity, title: draft.title,
            startsAt: draft.startsAt, durationMinutes: draft.durationMinutes,
            endsAt: draft.startsAt.addingTimeInterval(Double(draft.durationMinutes) * 60),
            capacity: draft.capacity, goingCount: 1, notes: draft.notes, place: draft.place,
            meetPoint: draft.meetPoint, autoRepost: draft.autoRepost, createdAt: now,
            myRole: .host, myJoinedAt: now, hasBlockedAttendee: false
        )
        game.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        games.append(game)
        attendees[game.id] = [Attendee(person: me, role: .host, joinedAt: now)]
        log(.created, game.id, actor: me)
        announceGameChange([game.id])
        return game
    }

    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game {
        try await beginWrite()
        let index = try writableIndex(id)
        let old = games[index]
        guard old.myRole == .host else { throw DomainError.notAllowed }
        if old.isCancelled { throw DomainError.cancelled }
        if old.hasEnded(now: now) { throw DomainError.ended }
        guard draft.capacity >= old.goingCount else { throw DomainError.capacityBelowGoing }
        // Only a new start time is checked: a game in progress can still fix its meet-up spot.
        try validate(draft, checksTime: draft.startsAt != old.startsAt)

        var new = old
        new.activity = draft.activity
        new.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        new.startsAt = draft.startsAt
        new.durationMinutes = draft.durationMinutes
        new.endsAt = draft.startsAt.addingTimeInterval(Double(draft.durationMinutes) * 60)
        new.capacity = draft.capacity
        new.notes = draft.notes
        new.place = draft.place
        new.meetPoint = draft.meetPoint
        new.autoRepost = draft.autoRepost

        let timeOrPlaceChanged = new.startsAt != old.startsAt || new.endsAt != old.endsAt || new.place != old.place
        let meetPointChanged = new.meetPoint != old.meetPoint
        if timeOrPlaceChanged || meetPointChanged { new.materialChangeAt = now }
        if old.isFull, !new.isFull, new.autoRepost { new.repostedAt = now }

        games[index] = new
        announceGameChange([new.id])
        if timeOrPlaceChanged { log(.timeOrPlaceChanged, id, actor: me) }
        if meetPointChanged { log(.meetPointUpdated, id, actor: me) }
        return new
    }

    func cancelGame(id: UUID) async throws -> Game {
        try await beginWrite()
        let index = try writableIndex(id)
        guard games[index].myRole == .host else { throw DomainError.notAllowed }
        if games[index].isCancelled { return games[index] }
        if games[index].hasEnded(now: now) { throw DomainError.ended }
        games[index].cancelledAt = now
        log(.cancelled, id, actor: me)
        announceGameChange([id])
        return games[index]
    }

    func joinGame(id: UUID) async throws -> Game {
        try await beginWrite()
        let index = try writableIndex(id)
        if losesNextJoinRace {
            losesNextJoinRace = false
            try? await Task.sleep(for: .seconds(1))
            fillGame(id: id)
        }
        let game = decorated(games[index])
        if game.myRole != nil { return game }
        if game.isCancelled { throw DomainError.cancelled }
        if game.hasEnded(now: now) { throw DomainError.ended }
        if game.hasBlockedAttendee { throw DomainError.blocked }
        if game.isFull { throw DomainError.full }

        games[index].goingCount += 1
        games[index].myRole = .player
        games[index].myJoinedAt = now
        attendees[id, default: []].append(Attendee(person: me, role: .player, joinedAt: now))
        log(.joined, id, actor: me)
        announceGameChange([id])
        return decorated(games[index])
    }

    func leaveGame(id: UUID) async throws -> Game {
        try await beginWrite()
        let index = try writableIndex(id)
        let game = games[index]
        if game.myRole == .host { throw DomainError.notAllowed }
        if game.hasEnded(now: now) { throw DomainError.ended }
        if game.myRole == nil { return decorated(game) }

        games[index].goingCount -= 1
        games[index].myRole = nil
        games[index].myJoinedAt = nil
        attendees[id]?.removeAll { $0.id == me.id }
        if game.isFull, game.autoRepost, !game.isCancelled { games[index].repostedAt = now }
        log(.left, id, actor: me)
        announceGameChange([id])
        return decorated(games[index])
    }

    // MARK: ProfileRepository

    func fetchMyProfile() async throws -> Profile? {
        try await begin()
        return profile
    }

    func updateProfile(_ input: ProfileInput) async throws -> Profile {
        try await beginWrite()
        let updated = try validated(input)
        profile = updated
        return updated
    }

    // MARK: SafetyRepository

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws {
        try await beginWrite()
        if case .message(let id) = target {
            // `report_message`: a message you can see, and not your own.
            let message = messages.values.joined().first { $0.id == id }
            guard let message, message.sender.id != me.id, isMember(of: message.gameID) else { throw DomainError.invalidInput }
        }
        reports.append((target, reason, note))
    }

    func block(userID: UUID) async throws {
        try await beginWrite()
        guard userID != me.id, people[userID] != nil else { throw DomainError.invalidInput }
        guard !blockedIDs.contains(userID) else { return }
        blockedIDs.insert(userID, at: 0)
    }

    func unblock(userID: UUID) async throws {
        try await beginWrite()
        blockedIDs.removeAll { $0 == userID }
    }

    func fetchBlockedPeople() async throws -> [PersonSummary] {
        try await begin()
        return blockedIDs.compactMap { people[$0] }
    }

    // MARK: ChatRepository

    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        try await begin()
        let visible = readableMessages(gameID).filter { before == nil || $0.createdAt <= before! }
        return Array(visible.suffix(limit))
    }

    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage] {
        try await begin()
        return readableMessages(gameID).filter { $0.createdAt >= since }
    }

    /// The same checks, in the same order, as `send_message`.
    func sendMessage(gameID: UUID, body: String, clientID: UUID) async throws -> ChatMessage {
        try await beginWrite()
        let game = try visibleGame(gameID)
        guard game.myRole != nil else { throw DomainError.notAllowed }
        if let sent = messages[gameID]?.first(where: { $0.sender.id == me.id && $0.clientID == clientID }) { return sent }
        guard chatEnabled else { throw DomainError.chatDisabled }
        if game.isCancelled { throw DomainError.cancelled }
        guard now < game.endsAt.addingTimeInterval(ChatMessage.closesAfterEnd) else { throw DomainError.ended }
        guard profile?.chatRulesAcceptedAt != nil else { throw DomainError.chatRulesRequired }
        let text = body.trimmingCharacters(in: .whitespaces)
        guard (1...ChatMessage.bodyLimit).contains(text.count), !TextFilter.hasLink(text), TextFilter.isFriendly(text) else {
            throw DomainError.invalidText
        }
        let lastMinute = messages.values.joined().filter { $0.sender.id == me.id && $0.createdAt > now.addingTimeInterval(-60) }
        guard lastMinute.count < 20 else { throw DomainError.rateLimited }

        let message = ChatMessage(id: UUID(), gameID: gameID, sender: me, body: text, clientID: clientID, createdAt: now)
        messages[gameID, default: []].append(message)
        announce(.message, in: gameID)
        return message
    }

    func acceptChatRules() async throws {
        try await beginWrite()
        if profile?.chatRulesAcceptedAt == nil { profile?.chatRulesAcceptedAt = now }
    }

    func markRead(gameID: UUID) async throws {
        try await beginWrite()
        if isMember(of: gameID) { lastRead[gameID] = now }
    }

    func fetchUnreadCounts() async throws -> [UUID: Int] {
        try await begin()
        var counts: [UUID: Int] = [:]
        for gameID in messages.keys {
            let unread = readableMessages(gameID).filter { message in
                message.sender.id != me.id && lastRead[gameID].map { message.createdAt > $0 } ?? true
            }
            if !unread.isEmpty { counts[gameID] = unread.count }
        }
        return counts
    }

    func updates(gameID: UUID) -> AsyncStream<ChatUpdate> {
        AsyncStream { continuation in
            let listener = UUID()
            listeners[gameID, default: [:]][listener] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.listeners[gameID]?[listener] = nil }
            }
        }
    }

    /// One campus in the mock, so `campus` isn't checked.
    func changes(campus: UUID) -> AsyncStream<GameChanges> {
        AsyncStream { continuation in
            let listener = UUID()
            gameChangeListeners[listener] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.gameChangeListeners[listener] = nil }
            }
        }
    }

    var gameChangeListenerCount: Int { gameChangeListeners.count }

    /// Pings like the server does. Tests call it to act as another phone changing a game.
    func announceGameChange(_ ids: Set<UUID>) {
        announce(.games(ids))
    }

    func announce(_ changes: GameChanges) {
        for listener in gameChangeListeners.values { listener.yield(changes) }
    }

    // MARK: AppConfigRepository

    func fetchAppConfig() async throws -> AppConfig {
        try await begin()
        var config = AppConfig.fallback
        config.chatEnabled = chatEnabled
        return config
    }

    func fetchActivities() async throws -> [Activity] {
        try await begin()
        return Activity.builtIn
    }

    func fetchUniversities() async throws -> [University] {
        try await begin()
        return universities
    }

    // MARK: Rules

    /// Exact domain match, like the auth hook: `@tec.mx`, not `@mail.tec.mx`.
    private func campus(for email: String, in campuses: [University]) -> University? {
        let domain = email.lowercased().split(separator: "@", maxSplits: 1).last.map(String.init)
        return email.contains("@") ? campuses.first { $0.emailDomain == domain } : nil
    }

    /// What RLS lets you read: nothing hosted by someone you blocked.
    private var visibleGames: [Game] {
        games.filter { !blockedIDs.contains($0.host.id) }.map(decorated)
    }

    private func visibleGame(_ id: UUID) throws -> Game {
        guard let game = visibleGames.first(where: { $0.id == id }) else { throw DomainError.notFound }
        return game
    }

    /// The map's rules: not cancelled, ended or full, starting within 7 days, newest bump first.
    /// - Parameter candidates: The games this reader may see.
    /// - Returns: The ones that belong on the map, in map order.
    private func onTheMap(_ candidates: [Game]) -> [Game] {
        candidates
            .filter { !$0.isCancelled && !$0.hasEnded(now: now) && !$0.isFull }
            .filter { $0.startsAt.timeIntervalSince(now) < GameDraft.postingWindow }
            .sorted { ($0.repostedAt ?? $0.createdAt) > ($1.repostedAt ?? $1.createdAt) }
    }

    /// What a `guest_games` row carries: nothing that names anyone or depends on who's asking.
    /// - Parameter game: The game as the mock stores it.
    /// - Returns: The same game with the host hidden and the per-viewer fields cleared.
    private static func asGuest(_ game: Game) -> Game {
        var game = game
        game.host = .hidden
        game.notes = nil
        game.meetPoint = nil
        game.materialChangeAt = nil
        game.autoRepost = false
        game.myRole = nil
        game.myJoinedAt = nil
        game.hasBlockedAttendee = false
        return game
    }

    /// `game_cards.has_blocked_attendee` is computed per reader.
    private func decorated(_ game: Game) -> Game {
        var game = game
        game.hasBlockedAttendee = (attendees[game.id] ?? []).contains { blockedIDs.contains($0.id) }
        return game
    }

    private func isMember(of gameID: UUID) -> Bool {
        games.contains { $0.id == gameID && $0.myRole != nil }
    }

    /// What RLS lets you read: chats of games you're in, without anyone you blocked.
    private func readableMessages(_ gameID: UUID) -> [ChatMessage] {
        guard isMember(of: gameID), !blockedIDs.contains(where: { blocked in games.contains { $0.id == gameID && $0.host.id == blocked } }) else { return [] }
        return (messages[gameID] ?? []).filter { !blockedIDs.contains($0.sender.id) }.sorted { $0.createdAt < $1.createdAt }
    }

    private func announce(_ update: ChatUpdate, in gameID: UUID) {
        for listener in (listeners[gameID] ?? [:]).values { listener.yield(update) }
    }

    private func writableIndex(_ id: UUID) throws -> Int {
        guard !blockedIDs.contains(where: { blocked in games.contains { $0.id == id && $0.host.id == blocked } }),
              let index = games.firstIndex(where: { $0.id == id })
        else { throw DomainError.notFound }
        return index
    }

    private func validate(_ draft: GameDraft, checksTime: Bool) throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...GameDraft.titleLimit).contains(title.count),
              GameDraft.durations.contains(draft.durationMinutes),
              GameDraft.capacityRange.contains(draft.capacity),
              (draft.notes?.count ?? 0) <= GameDraft.notesLimit,
              (draft.meetPoint?.count ?? 0) <= GameDraft.meetPointLimit,
              draft.activity.postable
        else { throw DomainError.invalidInput }
        guard [title, draft.notes ?? "", draft.meetPoint ?? ""].allSatisfy(TextFilter.isFriendly) else {
            throw DomainError.invalidText
        }
        if checksTime, draft.startsAt <= now || draft.startsAt.timeIntervalSince(now) >= GameDraft.postingWindow {
            throw DomainError.invalidTime
        }
    }

    private func validated(_ input: ProfileInput) throws -> Profile {
        let first = input.firstName.trimmingCharacters(in: .whitespaces)
        let last = input.lastName.trimmingCharacters(in: .whitespaces)
        guard (1...ProfileInput.nameLimit).contains(first.count),
              (1...ProfileInput.nameLimit).contains(last.count),
              !input.interests.isEmpty
        else { throw DomainError.invalidInput }
        guard TextFilter.isFriendly(first), TextFilter.isFriendly(last) else { throw DomainError.invalidText }
        return Profile(
            id: me.id, firstName: first, lastName: last, gradYear: input.gradYear,
            university: profile?.university ?? signInCampus, interests: input.interests,
            chatRulesAcceptedAt: profile?.chatRulesAcceptedAt
        )
    }

    private func log(_ kind: GameActivityEntry.Kind, _ gameID: UUID, actor: PersonSummary) {
        let entry = GameActivityEntry(id: UUID(), gameID: gameID, kind: kind, actor: actor, at: now)
        activity[gameID, default: []].append(entry)
        announce(.activity, in: gameID)
    }

    private func begin() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    /// Every write RPC checks `auth.uid()` and `is_active()` first.
    private func beginWrite() async throws {
        try await begin()
        if isSuspended { throw DomainError.suspended }
        if isAwaitingApproval { throw DomainError.pendingApproval }
        if case .signedOut = state { throw DomainError.notAuthenticated }
    }
}
#endif
