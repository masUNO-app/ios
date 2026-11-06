#if DEBUG
import Foundation
import Observation

/// One in-memory backend behind every protocol, for previews and tests. It enforces the
/// same rules and raises the same codes as the RPCs in `docs/API.md`, so code written
/// against it behaves the same on `masuno-dev`. Compiled out of Release (N27).
@Observable
final class MockBackend: AuthService, GameRepository, ProfileRepository, SafetyRepository, AppConfigRepository {
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
    /// Campuses taking sign-ups. Change this to launch somewhere else.
    var openUniversities = [MockFixtures.tec]
    /// `-raceJoin YES`: the next join waits a second, then loses the last spot to someone else.
    var losesNextJoinRace = false

    let me: PersonSummary
    private var attendees: [UUID: [Attendee]]
    private var activity: [UUID: [GameActivityEntry]] = [:]
    private var people: [UUID: PersonSummary]
    private var blockedIDs: [UUID] = []
    private var isSuspended = false
    /// The campus the email signing in belongs to.
    private var signInCampus = MockFixtures.tec

    /// `state` defaults to signed in with the Monterrey fixtures. Pass `.signedOut(email: nil)`
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
    func simulateDropOut(id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let game = games[index]
        guard game.goingCount > 1 else { return }
        games[index].goingCount -= 1
        if game.isFull, game.autoRepost, !game.isCancelled { games[index].repostedAt = now }
    }

    /// A moderator sets `banned_at`.
    func suspend() {
        isSuspended = true
        state = .suspended
    }

    /// The saved session stopped working.
    func expireSession(email: String?) {
        state = .signedOut(email: email)
    }

    // MARK: AuthService

    func restoreSession() async {
        if state == .loading { state = .signedOut(email: nil) }
    }

    func signInMethod(for email: String) async throws -> SignInMethod {
        try await begin()
        if email.lowercased() == MockFixtures.reviewEmail { return .password }
        guard campus(for: email) != nil else { throw DomainError.emailNotAllowed }
        return .otp
    }

    func sendCode(to email: String) async throws {
        try await begin()
        guard let campus = campus(for: email) else { throw DomainError.emailNotAllowed }
        signInCampus = campus
    }

    /// Any six digits work, except `000000` (wrong) and `111111` (expired).
    func verifyCode(_ code: String, email: String) async throws {
        try await begin()
        switch code {
        case "000000": throw DomainError.codeInvalid
        case "111111": throw DomainError.codeExpired
        default: state = profile == nil ? .needsProfile : .signedIn(userID: me.id)
        }
    }

    func signIn(email: String, password: String) async throws {
        try await begin()
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
        profile = try validated(input)
        state = .needsGuidelines
    }

    func acceptGuidelines() async throws {
        try await begin()
        state = .signedIn(userID: me.id)
    }

    func signOut() async throws {
        try await begin()
        state = .signedOut(email: nil)
    }

    /// Cancels upcoming hosted games and frees joined spots, like `delete-account` (B9).
    func deleteAccount() async throws {
        try await begin()
        for game in games where game.myRole != nil && !game.hasEnded(now: now) {
            if game.myRole == .host {
                _ = try await cancelGame(id: game.id)
            } else {
                _ = try await leaveGame(id: game.id)
            }
        }
        profile = nil
        state = .signedOut(email: nil)
    }

    // MARK: GameRepository

    func fetchMapGames() async throws -> [Game] {
        try await begin()
        return visibleGames
            .filter { !$0.isCancelled && !$0.hasEnded(now: now) && !$0.isFull }
            .filter { $0.startsAt.timeIntervalSince(now) < GameDraft.postingWindow }
            .sorted { ($0.repostedAt ?? $0.createdAt) > ($1.repostedAt ?? $1.createdAt) }
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

    // MARK: AppConfigRepository

    func fetchAppConfig() async throws -> AppConfig {
        try await begin()
        return .fallback
    }

    func fetchActivities() async throws -> [Activity] {
        try await begin()
        return Activity.builtIn
    }

    func fetchOpenUniversities() async throws -> [University] {
        try await begin()
        return openUniversities
    }

    // MARK: Rules

    /// Exact domain match, like the auth hook: `@tec.mx`, not `@mail.tec.mx`.
    private func campus(for email: String) -> University? {
        let domain = email.lowercased().split(separator: "@", maxSplits: 1).last.map(String.init)
        return email.contains("@") ? openUniversities.first { $0.emailDomain == domain } : nil
    }

    /// What RLS lets you read: nothing hosted by someone you blocked.
    private var visibleGames: [Game] {
        games.filter { !blockedIDs.contains($0.host.id) }.map(decorated)
    }

    private func visibleGame(_ id: UUID) throws -> Game {
        guard let game = visibleGames.first(where: { $0.id == id }) else { throw DomainError.notFound }
        return game
    }

    /// `game_cards.has_blocked_attendee` is computed per reader.
    private func decorated(_ game: Game) -> Game {
        var game = game
        game.hasBlockedAttendee = (attendees[game.id] ?? []).contains { blockedIDs.contains($0.id) }
        return game
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
            university: profile?.university ?? signInCampus, interests: input.interests
        )
    }

    private func log(_ kind: GameActivityEntry.Kind, _ gameID: UUID, actor: PersonSummary) {
        let entry = GameActivityEntry(id: UUID(), gameID: gameID, kind: kind, actor: actor, at: now)
        activity[gameID, default: []].append(entry)
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
        if case .signedOut = state { throw DomainError.notAuthenticated }
    }
}
#endif
