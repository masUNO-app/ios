import Foundation
import Observation

/// What the screens read and act on (SPEC §8.2, B6). Sits over the repositories: caches
/// games, shows joins and leaves right away and undoes them if the server says no, and
/// hides blocked people before the server answers (App Review checks this).
@Observable
final class GameStore {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(DomainError)
    }

    private(set) var mapState = LoadState.idle
    private(set) var myGamesState = LoadState.idle
    private(set) var profile: Profile?
    /// Your campus. Kept from the last launch, so the map has somewhere to open while offline.
    private(set) var campus: University?
    private(set) var activities = Activity.builtIn
    /// People you blocked, newest first.
    private(set) var blockedPeople: [PersonSummary] = []
    /// The last load couldn't reach the server, so what's on screen may be old.
    private(set) var isOffline = false
    /// Set after creating a game so the map can jump to it.
    private(set) var lastCreatedID: UUID?
    /// Short toast text (failed actions, confirmations).
    var notice: String?
    /// A call found the session gone or the account banned; the app re-checks `AuthService`.
    @ObservationIgnored var onSessionProblem: (() -> Void)?

    private var cache: [UUID: Game] = [:]
    private var mapIDs: [UUID] = []
    private var attendeesByGame: [UUID: [Attendee]] = [:]
    /// Each game's going count when its attendees were last fetched, to spot a stale list.
    @ObservationIgnored private var attendeeCounts: [UUID: Int] = [:]
    private var activityByGame: [UUID: [GameActivityEntry]] = [:]
    /// Games whose fetch came back `not_found`, so Event detail can say so.
    private var missingIDs: Set<UUID> = []
    private var savedIDs: Set<UUID> = []
    /// Saved full games you asked to hear about when a spot opens. On the phone, like Saved.
    private var spotAlertIDs: Set<UUID> = []
    /// Cancelled games you removed from Going.
    private var dismissedIDs: Set<UUID> = []
    private var unreadByGame: [UUID: Int] = [:]

    /// `app_config.chat_enabled`, set at launch. Off, group chat is the read-only hub (SPEC N14).
    var isChatEnabled = false

    /// Messaging for the chat screen, which keeps its own timeline (`ChatViewModel`).
    @ObservationIgnored let chat: any ChatRepository
    @ObservationIgnored private let games: any GameRepository
    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let safety: any SafetyRepository
    @ObservationIgnored private let catalog: any AppConfigRepository
    @ObservationIgnored private let defaults: UserDefaults
    /// Listens for game changes made on other phones, and the re-read they schedule.
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    /// What the pings since the last re-read named.
    @ObservationIgnored private var pendingChanges: GameChanges?
    /// One join writes a spot row and then the game row, so wait out a burst before re-reading.
    private static let refreshDebounce: Duration = .milliseconds(400)
    /// Shorter wait when this phone is in the game or has it saved: those screens should move
    /// with the other phone, not a second later.
    private static let fastRefreshDebounce: Duration = .milliseconds(200)
    /// Every phone on a campus hears the same ping, so each waits up to this much longer, at
    /// random, and their re-reads don't all reach the server in the same instant.
    private static let refreshSpreadMilliseconds = 0...600
    /// Waits before re-opening a games channel that dropped, longer each time it fails again.
    private static let reconnectDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]
    /// A channel that stayed open this long was connected, so pings may have been missed while it was down.
    private static let connectedLongEnough: Duration = .seconds(10)

    init(
        games: any GameRepository, profiles: any ProfileRepository, safety: any SafetyRepository,
        chat: any ChatRepository, catalog: any AppConfigRepository, defaults: UserDefaults = .standard
    ) {
        self.chat = chat
        self.games = games
        self.profiles = profiles
        self.safety = safety
        self.catalog = catalog
        self.defaults = defaults
        campus = defaults.data(forKey: Self.campusKey).flatMap { try? JSONDecoder().decode(University.self, from: $0) }
    }

    // MARK: Queries

    func game(_ id: UUID) -> Game? {
        cache[id].flatMap(visible)
    }

    /// A fetch said this game doesn't exist or is hidden from you.
    func isMissing(_ id: UUID) -> Bool {
        missingIDs.contains(id) || (cache[id] != nil && game(id) == nil)
    }

    /// Open games on the map, re-checked locally so a game that just filled or ended drops off.
    func mapGames(now: Date = .now) -> [Game] {
        mapIDs.compactMap(game).filter { game in
            !game.isCancelled && !game.hasEnded(now: now) && !game.isFull
        }
    }

    /// Upcoming games you joined, soonest first. Cancelled ones stay until you remove them.
    func goingGames(now: Date = .now) -> [Game] {
        visibleGames
            .filter { $0.myRole == .player && !$0.hasEnded(now: now) && !($0.isCancelled && dismissedIDs.contains($0.id)) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func hostedGames(now: Date = .now) -> [Game] {
        visibleGames
            .filter { $0.myRole == .host && !$0.isCancelled && !$0.hasEnded(now: now) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Games you were in that ended in the last 14 days, newest first, so you can still report someone.
    func pastGames(now: Date = .now) -> [Game] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        return visibleGames
            .filter { $0.isGoing && !$0.isCancelled && $0.hasEnded(now: now) && $0.endsAt > cutoff }
            .sorted { $0.startsAt > $1.startsAt }
    }

    /// Saved games that haven't ended, soonest first (N15).
    func savedGames(now: Date = .now) -> [Game] {
        visibleGames
            .filter { savedIDs.contains($0.id) && !$0.hasEnded(now: now) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func isSaved(_ id: UUID) -> Bool {
        savedIDs.contains(id)
    }

    /// "Spot alert is on": you'll hear when this full game has room.
    func hasSpotAlert(_ id: UUID) -> Bool {
        spotAlertIDs.contains(id)
    }

    /// A game's people and open spots, for token rows and the court. Before Who's going has
    /// loaded it's the host (and you, if you're in), with the rest as a count.
    func lineup(for game: Game) -> Lineup {
        Lineup(game: game, attendees: attendees(of: game.id), me: profile?.summary)
    }

    /// Who's going, minus anyone you just blocked. `goingCount` still includes them.
    func attendees(of id: UUID) -> [Attendee] {
        (attendeesByGame[id] ?? []).filter { !blockedIDs.contains($0.id) }
    }

    func activity(of id: UUID) -> [GameActivityEntry] {
        (activityByGame[id] ?? []).filter { entry in
            !(entry.actor.map { blockedIDs.contains($0.id) } ?? false)
        }
    }

    /// Messages you haven't seen in a game's chat, for "Group chat · 2 new".
    func unreadCount(_ id: UUID) -> Int {
        isChatEnabled ? unreadByGame[id] ?? 0 : 0
    }

    func isBlocked(_ personID: UUID) -> Bool {
        blockedIDs.contains(personID)
    }

    var postableActivities: [Activity] {
        activities.filter { $0.postable && $0.active }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var interestActivities: [Activity] {
        activities.filter { $0.interestSelectable && $0.active }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var visibleGames: [Game] {
        cache.values.compactMap(visible)
    }

    private func visible(_ game: Game) -> Game? {
        blockedIDs.contains(game.host.id) ? nil : game
    }

    private var blockedIDs: Set<UUID> {
        Set(blockedPeople.map(\.id))
    }

    // MARK: Loading

    /// Everything the signed-in app needs. Called on sign-in and launch.
    func load() async {
        await loadProfile()
        savedIDs = readSavedIDs()
        spotAlertIDs = readIDs(spotAlertKey).intersection(savedIDs)
        dismissedIDs = readIDs(dismissedKey)
        async let activities: Void = loadActivities()
        async let blocked: Void = loadBlockedPeople()
        async let map: Void = refreshMap()
        async let mine: Void = refreshMyGames()
        async let saved: Void = refreshSaved()
        async let unread: Void = refreshUnread()
        _ = await (activities, blocked, map, mine, saved, unread)
        listenForGameChanges()
    }

    /// On foreground and pull to refresh.
    func refresh() async {
        // The launch was offline and never got your profile: do the whole load now, which also
        // reads your saved games and starts listening for changes from other phones.
        guard profile != nil else { return await load() }
        async let map: Void = refreshMap()
        async let mine: Void = refreshMyGames()
        async let saved: Void = refreshSaved()
        async let unread: Void = refreshUnread()
        _ = await (map, mine, saved, unread)
    }

    /// Re-reads when a game or spot on your campus changes on another phone. Opens once per
    /// signed-in session; `reset()` closes it.
    private func listenForGameChanges() {
        guard changesTask == nil, let campus = profile?.university.id else { return }
        changesTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let stream = self?.games.changes(campus: campus) else { return }
                let opened = ContinuousClock.now
                for await changes in stream { self?.note(changes) }

                let wasConnected = ContinuousClock.now - opened >= Self.connectedLongEnough
                failures = wasConnected ? 0 : failures + 1
                let delay = Self.reconnectDelays[min(failures, Self.reconnectDelays.count - 1)]
                do { try await Task.sleep(for: delay) } catch { return }
                // Catch up on whatever changed while the channel was down.
                if wasConnected { self?.note(.unlisted) }
            }
        }
    }

    /// Collects what the pings name, then re-reads once they've been quiet for a moment.
    private func note(_ changes: GameChanges) {
        pendingChanges = switch (pendingChanges, changes) {
        case (nil, _): changes
        case (.games(let held), .games(let new)): .games(held.union(new))
        default: .unlisted
        }
        pendingRefresh?.cancel()
        let fast = wantsItFast(pendingChanges)
        pendingRefresh = Task { [weak self] in
            let spread = fast ? Duration.zero : Duration.milliseconds(Int.random(in: Self.refreshSpreadMilliseconds))
            let debounce = fast ? Self.fastRefreshDebounce : Self.refreshDebounce
            do { try await Task.sleep(for: debounce + spread) } catch { return }
            guard let self, let changes = pendingChanges else { return }
            pendingChanges = nil
            await refresh(after: changes)
        }
    }

    /// A game you're in, or one you saved, should update on this phone ahead of the crowd.
    /// - Parameter changes: The pings collected since the last re-read.
    /// - Returns: Whether to skip the random delay.
    private func wantsItFast(_ changes: GameChanges?) -> Bool {
        guard case .games(let ids) = changes else { return false }
        if !ids.isDisjoint(with: savedIDs) || !ids.isDisjoint(with: spotAlertIDs) { return true }
        return cache.values.contains { ids.contains($0.id) && $0.myRole != nil }
    }

    /// Re-reads only what a ping named: those games and their people, if this phone holds them,
    /// and the map when a game it hasn't seen might belong there. A game that just got a spot
    /// is put back on the map here, so a saved game doesn't wait on a second fetch.
    private func refresh(after changes: GameChanges) async {
        guard case .games(let ids) = changes else {
            async let lists: Void = refresh()
            async let held = refreshHeldGames(Set(cache.keys))
            _ = await (lists, held)
            return
        }
        let held = ids.filter { cache[$0] != nil }
        await refreshHeldGames(held)
        if held.count < ids.count { await refreshMap() }
    }

    /// Re-reads games this phone holds, and their people where Who's going was loaded. The game
    /// and its people land together, so a leave doesn't draw a dashed spot on the wrong face.
    /// A game that doesn't come back was deleted or is now hidden by a block, so it goes.
    /// - Parameter ids: Games already in the cache.
    private func refreshHeldGames(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let fetched: [Game]
        do {
            fetched = try await games.fetchGames(ids: Array(ids))
        } catch {
            noteFailure(domainError(error))
            return
        }

        let fetchedIDs = Set(fetched.map(\.id))
        // Fetched before anything is published, so the faces and the dashed spots change together.
        var people: [UUID: [Attendee]] = [:]
        for id in ids where attendeesByGame[id] != nil && fetchedIDs.contains(id) {
            people[id] = try? await games.fetchAttendees(gameID: id)
        }

        store(fetched)
        for id in ids.subtracting(fetchedIDs) {
            cache[id] = nil
            mapIDs.removeAll { $0 == id }
            attendeesByGame[id] = nil
            missingIDs.insert(id)
        }
        for (id, list) in people {
            attendeesByGame[id] = list
            attendeeCounts[id] = cache[id]?.goingCount
        }
        for game in fetched where !mapIDs.contains(game.id) && !game.isCancelled && !game.hasEnded() && !game.isFull {
            mapIDs.insert(game.id, at: 0)
        }
    }

    func refreshMap() async {
        if mapState != .loaded { mapState = .loading }
        do {
            let fetched = try await games.fetchMapGames()
            store(fetched)
            mapIDs = fetched.map(\.id)
            mapState = .loaded
            isOffline = false
        } catch {
            let error = domainError(error)
            noteFailure(error)
            // Keep showing what we have; only an empty map shows the retry card.
            mapState = mapIDs.isEmpty ? .failed(error) : .loaded
        }
    }

    func refreshMyGames() async {
        if myGamesState != .loaded { myGamesState = .loading }
        do {
            let fetched = try await games.fetchMyGames()
            // Anything we thought you were in that didn't come back, you're no longer in.
            let ids = Set(fetched.map(\.id))
            for (id, game) in cache where game.myRole != nil && !ids.contains(id) {
                cache[id]?.myRole = nil
                cache[id]?.myJoinedAt = nil
            }
            store(fetched)
            myGamesState = .loaded
            isOffline = false
        } catch {
            let error = domainError(error)
            noteFailure(error)
            myGamesState = myGamesState == .loading ? .failed(error) : myGamesState
        }
    }

    func refreshSaved() async {
        guard !savedIDs.isEmpty else { return }
        do {
            store(try await games.fetchGames(ids: Array(savedIDs)))
        } catch {
            noteFailure(domainError(error))
        }
    }

    /// Event detail for a game that isn't cached yet, or a refresh of one that is.
    func loadGame(_ id: UUID) async {
        do {
            store([try await games.fetchGame(id: id)])
            missingIDs.remove(id)
            isOffline = false
        } catch {
            let error = domainError(error)
            if error == .notFound {
                cache[id] = nil
                mapIDs.removeAll { $0 == id }
                missingIDs.insert(id)
            } else {
                noteFailure(error)
            }
        }
    }

    func loadAttendees(_ id: UUID) async {
        do {
            attendeesByGame[id] = try await games.fetchAttendees(gameID: id)
            attendeeCounts[id] = cache[id]?.goingCount
        } catch {
            noteFailure(domainError(error))
        }
    }

    /// Who's going for the games a list is about to draw tokens for, skipping any that are loaded
    /// and still match the game's count. Quiet: a failure just leaves the host's token and a count.
    func loadMissingAttendees(for ids: [UUID]) async {
        for id in ids where attendeesByGame[id] == nil || attendeeCounts[id] != cache[id]?.goingCount {
            if Task.isCancelled { return }
            guard let fetched = try? await games.fetchAttendees(gameID: id) else { continue }
            attendeesByGame[id] = fetched
            attendeeCounts[id] = cache[id]?.goingCount
        }
    }

    func loadActivity(_ id: UUID) async {
        do {
            activityByGame[id] = try await games.fetchActivity(gameID: id)
        } catch {
            noteFailure(domainError(error))
        }
    }

    /// Counts are a nicety: a failure leaves the last ones in place.
    func refreshUnread() async {
        guard isChatEnabled else { return }
        if let counts = try? await chat.fetchUnreadCounts() { unreadByGame = counts }
    }

    private func loadProfile() async {
        do {
            profile = try await profiles.fetchMyProfile()
            if let university = profile?.university { remember(campus: university) }
        } catch {
            noteFailure(domainError(error))
        }
    }

    private func loadActivities() async {
        // The built-in list stays if this fails.
        if let fetched = try? await catalog.fetchActivities(), !fetched.isEmpty { activities = fetched }
    }

    private func loadBlockedPeople() async {
        do {
            blockedPeople = try await safety.fetchBlockedPeople()
        } catch {
            noteFailure(domainError(error))
        }
    }

    private func store(_ fetched: [Game]) {
        var openedTitle: String?
        var alertsChanged = false
        for game in fetched {
            let wasFull = cache[game.id]?.isFull == true
            let watched = savedIDs.contains(game.id) || spotAlertIDs.contains(game.id)
            if watched, wasFull, !game.isFull, !game.isCancelled, !game.hasEnded(), !game.isGoing {
                openedTitle = game.title
            }
            if spotAlertIDs.contains(game.id), game.isCancelled || game.hasEnded() || game.isGoing || !game.isFull {
                spotAlertIDs.remove(game.id)
                alertsChanged = true
            }
            cache[game.id] = game
            missingIDs.remove(game.id)
        }
        if alertsChanged { write(spotAlertIDs, forKey: spotAlertKey) }
        if let openedTitle {
            notice = String(localized: "A spot just opened in \(openedTitle).")
        }
    }

    // MARK: Join and leave

    /// First come, first served: "You're in" shows immediately and rolls back if the server says no.
    func join(_ id: UUID) async {
        guard let before = game(id), !before.isGoing else { return }
        if before.hasBlockedAttendee { return fail(.blocked) }
        if before.isFull { return fail(.full) }

        var optimistic = before
        optimistic.goingCount += 1
        optimistic.myRole = .player
        optimistic.myJoinedAt = .now
        cache[id] = optimistic
        let attendeesBefore = attendeesByGame[id]
        if let me = profile?.summary, attendeesBefore != nil {
            attendeesByGame[id]?.append(Attendee(person: me, role: .player, joinedAt: .now))
        }

        do {
            cache[id] = try await games.joinGame(id: id)
        } catch {
            let error = domainError(error)
            cache[id] = before
            attendeesByGame[id] = attendeesBefore
            fail(error)
            // The phone's copy is out of date; show what really happened to the game.
            if error != .offline { await loadGame(id) }
        }
    }

    func leave(_ id: UUID) async {
        guard let before = game(id), before.myRole == .player else { return }

        var optimistic = before
        optimistic.goingCount -= 1
        optimistic.myRole = nil
        optimistic.myJoinedAt = nil
        cache[id] = optimistic
        let attendeesBefore = attendeesByGame[id]
        if let me = profile?.id { attendeesByGame[id]?.removeAll { $0.id == me } }

        do {
            cache[id] = try await games.leaveGame(id: id)
        } catch {
            cache[id] = before
            attendeesByGame[id] = attendeesBefore
            fail(domainError(error))
        }
    }

    // MARK: Hosting

    /// Throws so the form can show the error next to the fields.
    func createGame(_ draft: GameDraft) async throws {
        do {
            let game = try await games.createGame(draft)
            cache[game.id] = game
            mapIDs.insert(game.id, at: 0)
            lastCreatedID = game.id
        } catch {
            throw noteThrown(error)
        }
    }

    func updateGame(id: UUID, _ draft: GameDraft) async throws {
        do {
            cache[id] = try await games.updateGame(id: id, draft)
            activityByGame[id] = nil
        } catch {
            throw noteThrown(error)
        }
    }

    /// Host sets "where to meet" (group chat). Uses `update_game` with everything else unchanged.
    func updateMeetPoint(_ id: UUID, to spot: String?) async throws {
        guard let game = game(id) else { throw DomainError.notFound }
        var draft = GameDraft(game)
        draft.meetPoint = spot
        try await updateGame(id: id, draft)
        await loadActivity(id)
    }

    /// Soft cancel: the game stays visible to people going, marked cancelled.
    func cancelGame(_ id: UUID) async {
        do {
            cache[id] = try await games.cancelGame(id: id)
            notice = String(localized: "Game cancelled. We let everyone going know.")
        } catch {
            fail(domainError(error))
        }
    }

    // MARK: Group chat

    /// "Before you chat": I agree. Throws so the sheet can stay open.
    func acceptChatRules() async throws {
        do {
            try await chat.acceptChatRules()
            if profile?.chatRulesAcceptedAt == nil { profile?.chatRulesAcceptedAt = .now }
        } catch {
            throw noteThrown(error)
        }
    }

    /// Opening a chat, or reading a message as it arrives, clears its count.
    func markChatRead(_ id: UUID) async {
        unreadByGame[id] = nil
        try? await chat.markRead(gameID: id)
    }

    // MARK: Profile

    func updateProfile(_ input: ProfileInput) async throws {
        do {
            profile = try await profiles.updateProfile(input)
            if let university = profile?.university { remember(campus: university) }
        } catch {
            throw noteThrown(error)
        }
    }

    // MARK: Safety

    /// Throws so the sheet can stay open and offer a retry.
    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws {
        do {
            try await safety.report(target, reason: reason, note: note)
        } catch {
            throw noteThrown(error)
        }
    }

    /// Hides them right away; puts them back if the server refuses.
    func block(_ person: PersonSummary) async {
        guard person.id != profile?.id, !blockedIDs.contains(person.id) else { return }
        blockedPeople.insert(person, at: 0)
        let attendeesWithThem = attendeesByGame.filter { $0.value.contains { $0.id == person.id } }.keys
        for id in attendeesWithThem { cache[id]?.hasBlockedAttendee = true }
        do {
            try await safety.block(userID: person.id)
        } catch {
            blockedPeople.removeAll { $0.id == person.id }
            for id in attendeesWithThem { await loadGame(id) }
            fail(domainError(error))
        }
    }

    func unblock(_ person: PersonSummary) async {
        guard let index = blockedPeople.firstIndex(of: person) else { return }
        blockedPeople.remove(at: index)
        do {
            try await safety.unblock(userID: person.id)
            await refresh()
        } catch {
            blockedPeople.insert(person, at: index)
            fail(domainError(error))
        }
    }

    // MARK: Saved (on the phone, N15)

    func toggleSaved(_ id: UUID) {
        if savedIDs.contains(id) {
            savedIDs.remove(id)
            spotAlertIDs.remove(id)
            write(spotAlertIDs, forKey: spotAlertKey)
        } else {
            savedIDs.insert(id)
            notice = String(localized: "Saved. Find it under bookmarks.")
        }
        write(savedIDs, forKey: savedKey)
    }

    /// "Alert me if a spot opens" on a full game. Turning it on saves the game too, so it's in
    /// Saved games. The check runs on this phone whenever games load; there's no push yet.
    func toggleSpotAlert(_ id: UUID) {
        if spotAlertIDs.contains(id) {
            spotAlertIDs.remove(id)
        } else {
            spotAlertIDs.insert(id)
            savedIDs.insert(id)
            write(savedIDs, forKey: savedKey)
        }
        write(spotAlertIDs, forKey: spotAlertKey)
    }

    /// "Remove" on a cancelled game in Going. The game is still cancelled on the server; this
    /// only stops listing it here.
    func dismissCancelled(_ id: UUID) {
        dismissedIDs.insert(id)
        write(dismissedIDs, forKey: dismissedKey)
    }

    private static let campusKey = "lastCampus"

    private func remember(campus: University) {
        self.campus = campus
        defaults.set(try? JSONEncoder().encode(campus), forKey: Self.campusKey)
    }

    private var accountKey: String { profile?.id.uuidString ?? "signedOut" }
    private var savedKey: String { "savedGames.\(accountKey)" }
    private var spotAlertKey: String { "spotAlerts.\(accountKey)" }
    private var dismissedKey: String { "dismissedGames.\(accountKey)" }

    private func readSavedIDs() -> Set<UUID> {
        readIDs(savedKey)
    }

    private func readIDs(_ key: String) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func write(_ ids: Set<UUID>, forKey key: String) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }

    // MARK: Sign-out

    /// Clears everything held for this account. Saved games stay on the phone, by account.
    func reset() {
        changesTask?.cancel()
        changesTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingChanges = nil
        cache = [:]
        mapIDs = []
        attendeesByGame = [:]
        attendeeCounts = [:]
        activityByGame = [:]
        missingIDs = []
        savedIDs = []
        spotAlertIDs = []
        dismissedIDs = []
        unreadByGame = [:]
        blockedPeople = []
        profile = nil
        campus = nil
        defaults.removeObject(forKey: Self.campusKey)
        lastCreatedID = nil
        mapState = .idle
        myGamesState = .idle
        isOffline = false
        notice = nil
    }

    // MARK: Errors

    func domainError(_ error: any Error) -> DomainError {
        error as? DomainError ?? .unknown(String(describing: error))
    }

    /// A failed action: show why.
    private func fail(_ error: DomainError) {
        noteFailure(error)
        notice = error.message
    }

    /// A failed load or action: track offline and session problems, without a toast.
    func noteFailure(_ error: DomainError) {
        if error == .offline { isOffline = true }
        if error == .suspended || error == .notAuthenticated { onSessionProblem?() }
    }

    private func noteThrown(_ error: any Error) -> DomainError {
        let error = domainError(error)
        noteFailure(error)
        return error
    }
}
