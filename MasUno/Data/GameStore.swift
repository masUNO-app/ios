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
    /// For a guest, the campus being browsed, which isn't kept.
    private(set) var campus: University?
    /// Browsing signed out (SPEC R7-15): games come from `guest_games`, without names, and every
    /// account action is a no-op. `load()` and `reset()` end it.
    private(set) var isGuest = false
    /// Changes whenever account/guest context is cleared. Async readers must validate this after awaits.
    private(set) var sessionID = UUID()
    private(set) var activities = Activity.builtIn
    /// People you blocked, newest first.
    private(set) var blockedPeople: [PersonSummary] = [] {
        didSet { blockedIDs = Set(blockedPeople.map(\.id)) }
    }
    /// Your invite codes, oldest first (N37). Empty for a guest, or until they load.
    private(set) var invites: [Invite] = []
    /// The last load couldn't reach the server, so what's on screen may be old.
    var isOffline: Bool { !offlineResources.isEmpty }
    private var offlineResources: Set<String> = []
    /// Set after creating a game so the map can jump to it.
    private(set) var lastCreatedID: UUID?
    /// Short toast text (failed actions, confirmations).
    var notice: String?
    /// The primer may show after the first game you join or host. The view checks iOS hasn't been asked.
    var asksForNotificationPrimer = false
    /// Turn on was tapped, so closing the sheet is not another "Not now".
    var notificationPrimerAccepted = false
    /// A call found the session gone or the account banned; the app re-checks `AuthService`.
    @ObservationIgnored var onSessionProblem: (() -> Void)?

    private var cache: [UUID: Game] = [:]
    private var mapIDs: [UUID] = []
    private var attendeesByGame: [UUID: [Attendee]] = [:]
    /// Each game's going count when its attendees were last fetched, to spot a stale list.
    @ObservationIgnored private var attendeeCounts: [UUID: Int] = [:]
    @ObservationIgnored private var attendeeDates: [UUID: Date] = [:]
    @ObservationIgnored private var dirtyAttendees: Set<UUID> = []
    private(set) var attendeeRevision = 0
    /// A broad refresh may follow a block made on another phone. Chat screens discard cached
    /// identities when this changes; incoming blocker IDs are deliberately never disclosed.
    private(set) var privacyRevision = 0
    private var activityByGame: [UUID: [GameActivityEntry]] = [:]
    /// Games whose fetch came back `not_found`, so Event detail can say so.
    private var missingIDs: Set<UUID> = []
    private var savedIDs: Set<UUID> = []
    /// Saved full games you asked to hear about when a spot opens. Cached on the phone and synced.
    private var spotAlertIDs: Set<UUID> = []
    /// Alerts this phone already announced. Ignored until the server clears "Notify me".
    private var spentSpotAlerts: Set<UUID> = []
    /// The latest save or spot-alert write for a game. An older reply is ignored.
    private var savedGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var bookmarkTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var bookmarkSession = UUID()
    private var confirmedBookmarks: [UUID: (saved: Bool, alert: Bool)] = [:]
    /// Cancelled games you removed from Going.
    private var dismissedIDs: Set<UUID> = []
    private var unreadByGame: [UUID: Int] = [:]
    @ObservationIgnored private var pendingReadAcknowledgements: Set<UUID> = []
    @ObservationIgnored private var readAcknowledgementGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var mutationVersions: [UUID: Int] = [:]
    @ObservationIgnored private var activeMembershipWrites: Set<UUID> = []
    @ObservationIgnored private var membershipTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isCreatingGame = false
    @ObservationIgnored private var activeHostingWrites: Set<UUID> = []
    @ObservationIgnored private var mutedGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var muteTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var confirmedMute: [UUID: Bool] = [:]
    @ObservationIgnored private var safetyGeneration = 0
    @ObservationIgnored private var profileWriteGeneration = 0
    @ObservationIgnored private var readEpoch = 0
    @ObservationIgnored private var publishedEpoch: [UUID: Int] = [:]
    @ObservationIgnored private var retainedGameIDs: Set<UUID> = []
    @ObservationIgnored private var lastAccess: [UUID: Date] = [:]
    @ObservationIgnored private let listReads = SharedReadPool<String, [Game]>(resource: "game lists")
    @ObservationIgnored private let gameReads = SharedReadPool<UUID, Game>(resource: "game")
    @ObservationIgnored private let attendeeReads = SharedReadPool<UUID, [Attendee]>(resource: "attendees", limit: 4)
    @ObservationIgnored private let activityReads = SharedReadPool<UUID, [GameActivityEntry]>(resource: "activity")
    @ObservationIgnored private let profileReads = SharedReadPool<String, Profile?>(resource: "profile")
    @ObservationIgnored private let inviteReads = SharedReadPool<String, [Invite]>(resource: "invites")
    @ObservationIgnored private let peopleReads = SharedReadPool<String, [PersonSummary]>(resource: "blocked people")
    @ObservationIgnored private let catalogReads = SharedReadPool<String, [Activity]>(resource: "activities")
    @ObservationIgnored private let unreadReads = SharedReadPool<String, [UUID: Int]>(resource: "unread")
    @ObservationIgnored private var acknowledgementTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let acknowledgementReads = SharedReadPool<UUID, Void>(resource: "read acknowledgement")
    @ObservationIgnored private let sessionLoads = SharedReadPool<String, Void>(resource: "session load")

    /// `app_config.chat_enabled`, set at launch. Off, group chat is the read-only hub (SPEC N14).
    var isChatEnabled = false

    /// Messaging for the chat screen, which keeps its own timeline (`ChatViewModel`).
    @ObservationIgnored let chat: any ChatRepository
    @ObservationIgnored private let games: any GameRepository
    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let safety: any SafetyRepository
    @ObservationIgnored private let catalog: any AppConfigRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifications: (any NotificationRepository)?
    /// Listens for game changes made on other phones, and the re-read they schedule.
    @ObservationIgnored private var safetyTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    /// What the pings since the last re-read named.
    @ObservationIgnored private var pendingChanges: GameChanges?
    /// `markBetaTesterIfNeeded` already asked the server this session, whatever it answered.
    @ObservationIgnored private var hasAskedForBetaBadge = false
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
        chat: any ChatRepository, catalog: any AppConfigRepository, defaults: UserDefaults = .standard,
        notifications: (any NotificationRepository)? = nil
    ) {
        self.chat = chat
        self.games = games
        self.profiles = profiles
        self.notifications = notifications
        self.safety = safety
        self.catalog = catalog
        self.defaults = defaults
        campus = rememberedCampus
    }

    // MARK: Queries

    func game(_ id: UUID) -> Game? {
        lastAccess[id] = .now
        return cache[id].flatMap(visible)
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

    /// Who's going, minus anyone you just blocked. Peer blocks preserve the real going count;
    /// host/player blocks reconcile the removed RSVP after the server confirms the block.
    func attendees(of id: UUID) -> [Attendee] {
        guard !missingIDs.contains(id), cache[id].map({ visible($0) != nil }) ?? true else { return [] }
        return (attendeesByGame[id] ?? []).filter { !blockedIDs.contains($0.id) }
    }

    func activity(of id: UUID) -> [GameActivityEntry] {
        guard !missingIDs.contains(id), cache[id].map({ visible($0) != nil }) ?? true else { return [] }
        return (activityByGame[id] ?? []).filter { entry in
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

    private var blockedIDs: Set<UUID> = []

    private struct ReadStamp {
        let session: UUID
        let epoch: Int
        let privacy: Int
        let versions: [UUID: Int]
    }

    private func stamp() -> ReadStamp {
        readEpoch += 1
        return ReadStamp(session: sessionID, epoch: readEpoch, privacy: privacyRevision, versions: mutationVersions)
    }

    private func accepts(_ stamp: ReadStamp, game id: UUID? = nil) -> Bool {
        guard stamp.session == sessionID, stamp.privacy == privacyRevision, !Task.isCancelled else { return false }
        guard let id else { return true }
        return (stamp.versions[id] ?? 0) == (mutationVersions[id] ?? 0)
            && stamp.epoch >= (publishedEpoch[id] ?? 0)
            && !activeMembershipWrites.contains(id) && !activeHostingWrites.contains(id)
    }

    private func publish(_ fetched: [Game], stamp: ReadStamp, updateBookmarks: Bool = true) {
        guard accepts(stamp) else { return }
        let accepted = fetched.filter { accepts(stamp, game: $0.id) }.map { game in
            var updated = game
            if muteTasks[game.id] != nil { updated.chatMuted = cache[game.id]?.chatMuted ?? game.chatMuted }
            if bookmarkTasks[game.id] != nil {
                updated.isBookmarked = savedIDs.contains(game.id)
                updated.spotAlert = spotAlertIDs.contains(game.id)
            }
            return updated
        }
        for game in accepted { publishedEpoch[game.id] = stamp.epoch }
        store(accepted, updateBookmarks: updateBookmarks)
    }

    func succeeded(_ resource: String) { offlineResources.remove(resource) }

    private func failedRead(_ error: any Error, resource: String) {
        guard !OperationCancellation.isCancellation(error) else { return }
        noteFailure(domainError(error), resource: resource)
    }

    /// Navigation targets are retained even if they leave current lists; everything else is bounded.
    func retainGames(_ ids: Set<UUID>) { retainedGameIDs = ids }

    func pruneUnusedGames(now: Date = .now) {
        let pinned = Set(mapIDs).union(savedIDs).union(retainedGameIDs)
            .union(activeMembershipWrites).union(activeHostingWrites).union(bookmarkTasks.keys)
        let historyCutoff = now.addingTimeInterval(-14 * 24 * 3600)
        let cold = now.addingTimeInterval(-15 * 60)
        let removable = cache.values.filter {
            !pinned.contains($0.id) && (!$0.isGoing || $0.endsAt < historyCutoff)
                && (lastAccess[$0.id] ?? .distantPast) < cold
        }.map(\.id)
        for id in removable {
            cache[id] = nil
            attendeesByGame[id] = nil
            attendeeCounts[id] = nil
            attendeeDates[id] = nil
            activityByGame[id] = nil
            lastAccess[id] = nil
            publishedEpoch[id] = nil
            dirtyAttendees.remove(id)
            missingIDs.remove(id)
        }
    }

    // MARK: Loading

    /// Everything the signed-in app needs. Called on sign-in and launch. Coming from guest mode it
    /// starts clean, so no nameless preview is left in a list.
    func load() async {
        if isGuest { clearSession(); campus = rememberedCampus }
        let context = sessionID
        do {
            try await sessionLoads.value(for: "load") { [self] in
                await loadProfile()
                guard context == sessionID, !Task.isCancelled else { return }
                savedIDs = readSavedIDs()
                spotAlertIDs = readIDs(spotAlertKey).intersection(savedIDs)
                dismissedIDs = readIDs(dismissedKey)
                async let activities: Void = loadActivities()
                async let blocked: Void = loadBlockedPeople()
                async let map: Void = refreshMap()
                async let mine: Void = refreshMyGames()
                async let saved: Void = importAndRefreshBookmarks()
                async let unread: Void = refreshUnread()
                _ = await (activities, blocked, map, mine, saved, unread)
                guard context == sessionID, !Task.isCancelled else { return }
                listenForGameChanges()
                pruneUnusedGames()
            }
        } catch { /* Reset or a departing caller does not change valid presentation state. */ }
        // A profile lookup can discover an account switch and rotate the context itself.
        // Populate that new account through a new shared load, never through the old flight.
        if context != sessionID, profile != nil, !isGuest, !Task.isCancelled { await load() }
    }

    private func importAndRefreshBookmarks() async {
        let context = sessionID
        await importBookmarksIfNeeded()
        guard context == sessionID, !Task.isCancelled else { return }
        await refreshSaved()
    }

    /// Browsing signed out (SPEC R7-15): a campus's open games, without names, notes or meet-up
    /// spots. Starts clean, like `reset()`, and loads no profile, saved games, blocks, Me or chat,
    /// and opens no live listener: those all need an account. The campus stays in memory only;
    /// the one kept on the phone is the signed-in account's, for opening the map offline.
    /// - Parameter campus: The campus to browse, picked by the guest.
    func loadGuest(campus: University) async {
        clearSession()
        isGuest = true
        self.campus = campus
        // The map first, so games show sooner; the built-in sports stand in until the list arrives.
        await refreshGuestMap()
        await loadActivities()
    }

    /// On foreground and pull to refresh.
    func refresh() async {
        if isGuest { _ = await refreshGuestMap(); return }
        guard profile != nil else { return await load() }
        let context = sessionID
        invalidatePrivacy()
        let revision = privacyRevision
        async let map: Void = refreshMap()
        async let mine: Void = refreshMyGames()
        async let saved: Void = refreshSaved()
        async let unread: Void = refreshUnread()
        async let blocks: Void = loadBlockedPeople()
        _ = await (map, mine, saved, unread, blocks)
        guard context == sessionID, revision == privacyRevision, !Task.isCancelled else { return }
        // A blocked host's game may vanish from every list while its old detail/saved row is
        // still held in memory. Reauthorize every cached row, not just games still on the map.
        await refreshHeldGames(Set(cache.keys), reauthorizing: true)
        guard context == sessionID, revision == privacyRevision, !Task.isCancelled else { return }
        if offlineResources.isDisjoint(with: ["map", "mine", "saved", "profile"]) { succeeded("general") }
        pruneUnusedGames()
    }

    private func invalidatePrivacy() {
        privacyRevision += 1
        listReads.cancelAll()
        gameReads.cancelAll()
        attendeeReads.cancelAll()
        activityReads.cancelAll()
        unreadReads.cancelAll()
        peopleReads.cancelAll()
        // Keep the loaded keys, so reconciliation also reloads lists that were emptied by
        // an earlier invalidation whose network requests were interrupted.
        attendeesByGame = attendeesByGame.mapValues { _ in [] }
        attendeeCounts = [:]
        attendeeDates = [:]
        dirtyAttendees.formUnion(attendeesByGame.keys)
        activityByGame = activityByGame.mapValues { _ in [] }
        unreadByGame = [:]
        attendeeRevision += 1
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
        // The first ping owns a bounded delay. New pings merge without postponing it or
        // cancelling a refresh already in progress; the loop drains follow-up invalidations.
        guard pendingRefresh == nil else { return }
        let context = sessionID
        pendingRefresh = Task { [weak self] in
            guard let self else { return }
            defer { if context == sessionID { pendingRefresh = nil } }
            while !Task.isCancelled, context == sessionID, pendingChanges != nil {
                let fast = wantsItFast(pendingChanges)
                let spread = fast ? Duration.zero : Duration.milliseconds(Int.random(in: Self.refreshSpreadMilliseconds))
                do { try await Task.sleep(for: (fast ? Self.fastRefreshDebounce : Self.refreshDebounce) + spread) }
                catch { return }
                guard context == sessionID, let changes = pendingChanges else { return }
                pendingChanges = nil
                await refresh(after: changes)
            }
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
        let context = sessionID
        guard case .games(let ids) = changes else {
            await refresh()
            return
        }
        dirtyAttendees.formUnion(ids)
        attendeeRevision += 1
        let held = ids.filter { cache[$0] != nil }
        await refreshHeldGames(held)
        guard context == sessionID, !isGuest else { return }
        if held.count < ids.count { await refreshMap() }
    }

    /// Re-reads games this phone holds, and their people where Who's going was loaded. The game
    /// and its people land together, so a leave doesn't draw a dashed spot on the wrong face.
    /// A game that doesn't come back was deleted or is now hidden by a block, so it goes.
    /// - Parameter ids: Games already in the cache.
    private func refreshHeldGames(_ ids: Set<UUID>, reauthorizing: Bool = false) async {
        guard !ids.isEmpty, !isGuest else { return }
        let snapshot = stamp()
        do {
            let fetched = try await fetchGameBatch(ids)
            guard accepts(snapshot) else { return }
            let fetchedIDs = Set(fetched.map(\.id))
            let needsPeople = ids.filter { attendeesByGame[$0] != nil && fetchedIDs.contains($0) }
            var people: [UUID: [Attendee]] = [:]
            let needsActivity = ids.filter { activityByGame[$0] != nil && fetchedIDs.contains($0) }
            let activityTasks = needsActivity.map { id in
                Task { @MainActor [self] in
                    let rows = try? await activityReads.value(for: id) { [games] in try await games.fetchActivity(gameID: id) }
                    return (id, rows)
                }
            }
            var activity: [UUID: [GameActivityEntry]] = [:]
            let peopleTasks = needsPeople.map { id in
                Task { @MainActor [self] in
                    let list = try? await attendeeReads.value(for: id) { [games] in try await games.fetchAttendees(gameID: id) }
                    return (id, list)
                }
            }
            await withTaskCancellationHandler {
                for task in peopleTasks {
                    let (id, list) = await task.value
                    if let list { people[id] = list }
                }
                for task in activityTasks {
                    let (id, rows) = await task.value
                    if let rows { activity[id] = rows }
                }
            } onCancel: {
                for task in peopleTasks { task.cancel() }
                for task in activityTasks { task.cancel() }
            }
            guard accepts(snapshot) else { return }
            // Names and count are published in the same main-actor turn.
            publish(fetched, stamp: snapshot)
            for id in ids.subtracting(fetchedIDs) where accepts(snapshot, game: id)
                || (reauthorizing && snapshot.versions[id] == mutationVersions[id]) {
                cache[id] = nil
                mapIDs.removeAll { $0 == id }
                attendeesByGame[id] = nil
                attendeeCounts[id] = nil
                attendeeDates[id] = nil
                activityByGame[id] = nil
                unreadByGame[id] = nil
                dirtyAttendees.remove(id)
                missingIDs.insert(id)
            }
            for (id, rows) in activity where accepts(snapshot, game: id) {
                activityByGame[id] = rows
            }
            for (id, list) in people where accepts(snapshot, game: id) {
                attendeesByGame[id] = list
                attendeeCounts[id] = cache[id]?.goingCount
                attendeeDates[id] = .now
                dirtyAttendees.remove(id)
            }
            for game in fetched where accepts(snapshot, game: game.id) && !mapIDs.contains(game.id)
                && !game.isCancelled && !game.hasEnded() && !game.isFull {
                mapIDs.insert(game.id, at: 0)
            }
        } catch {
            guard snapshot.session == sessionID else { return }
            failedRead(error, resource: "held")
        }
    }

    private func fetchGameBatch(_ ids: Set<UUID>) async throws -> [Game] {
        let ordered = ids.sorted { $0.uuidString < $1.uuidString }
        var result: [Game] = []
        for start in stride(from: 0, to: ordered.count, by: 100) {
            try Task.checkCancellation()
            let chunk = Array(ordered[start..<min(start + 100, ordered.count)])
            let key = "ids:" + chunk.map(\.uuidString).joined(separator: ",")
            result += try await listReads.value(for: key) { [games] in try await games.fetchGames(ids: chunk) }
        }
        return result
    }

    func refreshMap() async {
        if isGuest { _ = await refreshGuestMap(); return }
        let snapshot = stamp()
        let previous = mapState
        if mapState != .loaded { mapState = .loading }
        do {
            let fetched = try await listReads.value(for: "map") { [games] in try await games.fetchMapGames() }
            guard accepts(snapshot), !isGuest else { return }
            publish(fetched, stamp: snapshot)
            let changedDuringRead = mapIDs.filter {
                (snapshot.versions[$0] ?? 0) != (mutationVersions[$0] ?? 0)
                    || activeMembershipWrites.contains($0) || activeHostingWrites.contains($0)
            }
            let fetchedIDs = fetched.map(\.id)
            let fetchedSet = Set(fetchedIDs)
            mapIDs = fetchedIDs + changedDuringRead.filter { !fetchedSet.contains($0) }
            mapState = .loaded
            succeeded("map")
        } catch {
            guard snapshot.session == sessionID, !isGuest else { return }
            if OperationCancellation.isCancellation(error) {
                if mapState == .loading { mapState = previous == .loading ? .idle : previous }
                return
            }
            failedRead(error, resource: "map")
            mapState = mapIDs.isEmpty ? .failed(domainError(error)) : .loaded
        }
    }

    /// The guest map, with the same loading, failed and offline states as `refreshMap`. A result
    /// that lands after sign-in, or after switching campus, is dropped so it can't mix nameless
    /// games into the account's lists.
    /// - Returns: The games now on the guest map, or nil if the fetch failed or was dropped.
    @discardableResult
    private func refreshGuestMap() async -> Set<UUID>? {
        guard let browsing = campus else { return nil }
        let snapshot = stamp()
        let previous = mapState
        if mapState != .loaded { mapState = .loading }
        do {
            let fetched = try await listReads.value(for: "guest-map") { [games] in
                try await games.fetchGuestGames(campus: browsing.id)
            }
            guard accepts(snapshot), isGuest, campus?.id == browsing.id else { return nil }
            publish(fetched, stamp: snapshot)
            mapIDs = fetched.map(\.id)
            mapState = .loaded
            succeeded("map")
            return Set(mapIDs)
        } catch {
            guard snapshot.session == sessionID, isGuest, campus?.id == browsing.id else { return nil }
            if OperationCancellation.isCancellation(error) {
                if mapState == .loading { mapState = previous == .loading ? .idle : previous }
                return nil
            }
            failedRead(error, resource: "map")
            mapState = mapIDs.isEmpty ? .failed(domainError(error)) : .loaded
            return nil
        }
    }

    func refreshMyGames() async {
        guard !isGuest else { return }
        let snapshot = stamp()
        let previous = myGamesState
        if myGamesState != .loaded { myGamesState = .loading }
        do {
            let fetched = try await listReads.value(for: "mine") { [games] in try await games.fetchMyGames() }
            guard accepts(snapshot), !isGuest else { return }
            let ids = Set(fetched.map(\.id))
            for (id, game) in cache where game.myRole != nil && !ids.contains(id) && accepts(snapshot, game: id) {
                cache[id]?.myRole = nil
                cache[id]?.myJoinedAt = nil
                publishedEpoch[id] = snapshot.epoch
            }
            publish(fetched, stamp: snapshot)
            myGamesState = .loaded
            succeeded("mine")
        } catch {
            guard snapshot.session == sessionID, !isGuest else { return }
            if OperationCancellation.isCancellation(error) {
                if myGamesState == .loading { myGamesState = previous == .loading ? .idle : previous }
                return
            }
            failedRead(error, resource: "mine")
            myGamesState = previous == .loaded ? .loaded : .failed(domainError(error))
        }
    }

    func refreshSaved() async {
        guard !isGuest else { return }
        let session = bookmarkSession
        let snapshot = stamp()
        let generations = savedGeneration
        let pending = Set(bookmarkTasks.keys)
        let localIDs = savedIDs
        do {
            // Fetch both parts before changing the cache: a failed refresh keeps local saves.
            let bookmarked = try await listReads.value(for: "saved") { [games] in try await games.fetchBookmarkedGames() }
            let onlyLocal = localIDs.subtracting(bookmarked.map(\.id))
            let older = onlyLocal.isEmpty ? [] : try await fetchGameBatch(onlyLocal)
            guard bookmarkSession == session, accepts(snapshot) else { return }
            for game in bookmarked + older where accepts(snapshot, game: game.id) {
                let unchanged = generations[game.id] == savedGeneration[game.id]
                    && !pending.contains(game.id) && bookmarkTasks[game.id] == nil
                publish([game], stamp: snapshot, updateBookmarks: unchanged)
                guard unchanged else { continue }
                confirmedBookmarks[game.id] = (game.isBookmarked, game.spotAlert)
                // A missing row in the 14-day query may still be an older bookmark. Only
                // explicit server flags (including the fallback) confirm remote removals.
                if !game.isBookmarked { savedIDs.remove(game.id) }
                if !game.isBookmarked || !game.spotAlert { spotAlertIDs.remove(game.id) }
            }
            write(savedIDs, forKey: savedKey)
            write(spotAlertIDs, forKey: spotAlertKey)
            succeeded("saved")
        } catch {
            if bookmarkSession == session { failedRead(error, resource: "saved") }
        }
    }

    /// Event detail for a game that isn't cached yet, or a refresh of one that is. A guest can't
    /// read `game_cards`, so the guest map is re-read instead, and a game no longer on it is missing.
    func loadGame(_ id: UUID) async {
        let snapshot = stamp()
        if isGuest {
            guard let listed = await refreshGuestMap(), accepts(snapshot), !listed.contains(id) else { return }
            cache[id] = nil
            missingIDs.insert(id)
            return
        }
        do {
            let fetched = try await gameReads.value(for: id) { [games] in try await games.fetchGame(id: id) }
            guard accepts(snapshot, game: id) else { return }
            publish([fetched], stamp: snapshot)
            missingIDs.remove(id)
            succeeded("game:\(id)")
        } catch {
            guard accepts(snapshot, game: id), !OperationCancellation.isCancellation(error) else { return }
            if domainError(error) == .notFound {
                cache[id] = nil
                mapIDs.removeAll { $0 == id }
                attendeesByGame[id] = nil
                attendeeCounts[id] = nil
                attendeeDates[id] = nil
                activityByGame[id] = nil
                unreadByGame[id] = nil
                dirtyAttendees.remove(id)
                missingIDs.insert(id)
            } else { failedRead(error, resource: "game:\(id)") }
        }
    }

    /// Who's going. Names need an account, so a guest's call does nothing.
    func loadAttendees(_ id: UUID) async {
        guard !isGuest else { return }
        let context = sessionID
        let version = mutationVersions[id] ?? 0
        let revision = privacyRevision
        do {
            let fetched = try await attendeeReads.value(for: id) { [games] in try await games.fetchAttendees(gameID: id) }
            guard context == sessionID, revision == privacyRevision, !Task.isCancelled, !isGuest,
                  version == (mutationVersions[id] ?? 0), !activeMembershipWrites.contains(id) else { return }
            attendeesByGame[id] = fetched
            attendeeCounts[id] = cache[id]?.goingCount
            attendeeDates[id] = .now
            dirtyAttendees.remove(id)
            succeeded("attendees:\(id)")
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "attendees:\(id)")
        }
    }

    /// Who's going for the games a list is about to draw tokens for, skipping any that are loaded
    /// and still match the game's count. Quiet: a failure just leaves the host's token and a count.
    func loadMissingAttendees(for ids: [UUID]) async {
        guard !isGuest else { return }
        let needed = Array(Set(ids)).filter {
            attendeesByGame[$0] == nil || attendeeCounts[$0] != cache[$0]?.goingCount
                || dirtyAttendees.contains($0) || (attendeeDates[$0] ?? .distantPast) < Date.now.addingTimeInterval(-120)
        }
        let context = sessionID
        // The shared pool limits actual HTTP work globally to four, including other screens.
        let tasks = needed.map { id in
            Task { @MainActor [weak self] in
                guard let self, context == sessionID else { return }
                await loadAttendees(id)
            }
        }
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            for task in tasks { task.cancel() }
        }
    }

    /// Group chat system rows. They name people, so a guest's call does nothing.
    func loadActivity(_ id: UUID) async {
        guard !isGuest else { return }
        let context = sessionID
        let revision = privacyRevision
        do {
            let fetched = try await activityReads.value(for: id) { [games] in try await games.fetchActivity(gameID: id) }
            guard context == sessionID, revision == privacyRevision, !Task.isCancelled, !isGuest else { return }
            activityByGame[id] = fetched
            succeeded("activity:\(id)")
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "activity:\(id)")
        }
    }

    /// Counts are a nicety: a failure leaves the last ones in place.
    func refreshUnread() async {
        guard isChatEnabled, !isGuest else { return }
        let context = sessionID
        let revision = privacyRevision
        // Retry acknowledgements first, while retaining optimistic local clearing for failed ones.
        for id in pendingReadAcknowledgements { await markChatRead(id) }
        do {
            let counts = try await unreadReads.value(for: "unread") { [chat] in try await chat.fetchUnreadCounts() }
            guard context == sessionID, revision == privacyRevision, !Task.isCancelled, !isGuest else { return }
            unreadByGame = counts.filter { !pendingReadAcknowledgements.contains($0.key) }
            succeeded("unread")
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "unread")
        }
    }

    /// Your invite codes. Quiet: a failure leaves the last ones in place. Codes need an account, so a
    /// guest's call does nothing.
    func loadInvites() async {
        guard !isGuest else { return }
        let context = sessionID
        do {
            let fetched = try await inviteReads.value(for: "invites") { [profiles] in try await profiles.fetchInvites() }
            guard context == sessionID, !Task.isCancelled, !isGuest else { return }
            invites = fetched
        } catch {
            guard context == sessionID else { return }
            if !OperationCancellation.isCancellation(error), [.notAuthenticated, .suspended].contains(domainError(error)) {
                noteFailure(domainError(error))
            }
        }
    }

    /// The beta tester badge (N37): on a TestFlight build, tells the server once per session if the
    /// profile isn't flagged yet. The app passes `await BuildChannel.isTestFlight` after `load()`,
    /// for example from the signed-in root's `.task`:
    /// `await store.markBetaTesterIfNeeded(isTestFlight: await BuildChannel.isTestFlight)`.
    /// Quiet, and a failure isn't retried until the next sign-in or launch.
    /// - Parameter isTestFlight: Whether this install came from TestFlight.
    func markBetaTesterIfNeeded(isTestFlight: Bool) async {
        guard isTestFlight, !isGuest, !hasAskedForBetaBadge, let current = profile, !current.isBetaTester else { return }
        let context = sessionID
        let version = profileWriteGeneration
        hasAskedForBetaBadge = true
        guard let updated = try? await profiles.markBetaTester(), updated.id == profile?.id, context == sessionID, version == profileWriteGeneration, !Task.isCancelled else { return }
        profile = updated
    }

    private func loadProfile() async {
        let context = sessionID
        let version = profileWriteGeneration
        do {
            let fetched = try await profileReads.value(for: "profile") { [profiles] in try await profiles.fetchMyProfile() }
            guard context == sessionID, version == profileWriteGeneration, !Task.isCancelled else { return }
            if let previous = profile?.id, previous != fetched?.id {
                clearSession()
            }
            profile = fetched
            if let university = fetched?.university { remember(campus: university) }
            succeeded("profile")
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "profile")
        }
    }

    private func loadActivities() async {
        let context = sessionID
        do {
            let fetched = try await catalogReads.value(for: "activities") { [catalog] in try await catalog.fetchActivities() }
            guard context == sessionID, !Task.isCancelled, !fetched.isEmpty else { return }
            activities = fetched
        } catch { /* Retain the built-in catalog, including after cancellation. */ }
    }

    private func loadBlockedPeople() async {
        let context = sessionID
        let version = safetyGeneration
        do {
            let fetched = try await peopleReads.value(for: "blocks") { [safety] in try await safety.fetchBlockedPeople() }
            guard context == sessionID, version == safetyGeneration, !Task.isCancelled else { return }
            blockedPeople = fetched
            succeeded("blocks")
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "blocks")
        }
    }

    private func store(_ fetched: [Game], updateBookmarks: Bool = true) {
        var alertsChanged = false
        var savedChanged = false
        for game in fetched {
            noteSpotOpened(replacing: cache[game.id], with: game)
            if updateBookmarks && bookmarkTasks[game.id] == nil {
                let spent = spotAlertIDs.contains(game.id)
                    && !game.isFull && !game.isCancelled && !game.hasEnded() && !game.isGoing
                if spotAlertIDs.contains(game.id), game.isCancelled || game.hasEnded() || game.isGoing || !game.isFull {
                    spotAlertIDs.remove(game.id)
                    alertsChanged = true
                    if spent { spentSpotAlerts.insert(game.id) }
                }
                if !game.spotAlert { spentSpotAlerts.remove(game.id) }
                // A server bookmark is added to the phone cache. A missing flag doesn't remove one:
                // the local list is what a relaunch reads before the network answers.
                if game.isBookmarked, savedIDs.insert(game.id).inserted { savedChanged = true }
                let stillWaiting = game.isFull && !game.isCancelled && !game.hasEnded() && !game.isGoing
                if game.spotAlert, stillWaiting, !spentSpotAlerts.contains(game.id) {
                    if spotAlertIDs.insert(game.id).inserted { alertsChanged = true }
                    if savedIDs.insert(game.id).inserted { savedChanged = true }
                }
            }
            cache[game.id] = game
            missingIDs.remove(game.id)
        }
        if alertsChanged { write(spotAlertIDs, forKey: spotAlertKey) }
        if savedChanged { write(savedIDs, forKey: savedKey) }
    }

    /// A saved game, or one with "Notify me", going from full to open. The bookmark reply can
    /// land this row before the change ping does, so both writes check the transition.
    private func noteSpotOpened(replacing previous: Game?, with game: Game) {
        let watched = savedIDs.contains(game.id) || spotAlertIDs.contains(game.id)
        guard let previous, previous.isFull, watched, !game.isFull, !game.isCancelled, !game.hasEnded(), !game.isGoing else { return }
        notice = String(localized: "A spot just opened in \(game.title).")
        if !mapIDs.contains(game.id) { mapIDs.insert(game.id, at: 0) }
    }

    // MARK: Join and leave

    /// First come, first served: "You're in" shows immediately and rolls back if the server says no.
    func join(_ id: UUID) async {
        let context = sessionID
        while let pending = membershipTasks[id] {
            await pending.value
            guard context == sessionID else { return }
        }
        guard !isGuest, context == sessionID, let before = game(id), !before.isGoing else { return }
        if before.hasBlockedAttendee { return fail(.blocked) }
        if before.isFull { return fail(.full) }
        let attendeesBefore = beginMembership(id, joining: true, before: before)
        let task = Task { [self] in
            defer { if context == sessionID { membershipTasks[id] = nil } }
            await changeMembership(id, joining: true, before: before, attendeesBefore: attendeesBefore, context: context)
        }
        membershipTasks[id] = task
        await task.value
    }

    func leave(_ id: UUID) async {
        let context = sessionID
        while let pending = membershipTasks[id] {
            await pending.value
            guard context == sessionID else { return }
        }
        guard !isGuest, context == sessionID, let before = game(id), before.myRole == .player else { return }
        let attendeesBefore = beginMembership(id, joining: false, before: before)
        let task = Task { [self] in
            defer { if context == sessionID { membershipTasks[id] = nil } }
            await changeMembership(id, joining: false, before: before, attendeesBefore: attendeesBefore, context: context)
        }
        membershipTasks[id] = task
        await task.value
    }

    private func beginMembership(_ id: UUID, joining: Bool, before: Game) -> [Attendee]? {
        activeMembershipWrites.insert(id)
        mutationVersions[id, default: 0] += 1
        var optimistic = before
        optimistic.goingCount += joining ? 1 : -1
        optimistic.myRole = joining ? .player : nil
        optimistic.myJoinedAt = joining ? .now : nil
        cache[id] = optimistic
        let attendeesBefore = attendeesByGame[id]
        if let me = profile?.summary, attendeesBefore != nil {
            if joining { attendeesByGame[id]?.append(Attendee(person: me, role: .player, joinedAt: .now)) }
            else { attendeesByGame[id]?.removeAll { $0.id == me.id } }
        }
        return attendeesBefore
    }

    private func changeMembership(_ id: UUID, joining: Bool, before: Game, attendeesBefore: [Attendee]?, context: UUID) async {
        guard context == sessionID, !isGuest else { return }
        let revision = privacyRevision
        do {
            let game = try await (joining ? games.joinGame(id: id) : games.leaveGame(id: id))
            guard context == sessionID else { return }
            guard revision == privacyRevision else {
                activeMembershipWrites.remove(id)
                mutationVersions[id, default: 0] += 1
                await loadGame(id)
                return
            }
            applyWrite(game)
            if joining { asksForNotificationPrimer = true }
            succeeded("membership:\(id)")
        } catch {
            guard context == sessionID else { return }
            if revision == privacyRevision, !OperationCancellation.isCancellation(error) {
                cache[id] = before
                attendeesByGame[id] = attendeesBefore
                failedRead(error, resource: "membership:\(id)")
                notice = domainError(error).message
            }
            activeMembershipWrites.remove(id)
            mutationVersions[id, default: 0] += 1
            // Cancellation/offline can be an uncertain server outcome. Reconcile; never replay the write.
            await loadGame(id)
            return
        }
        guard context == sessionID else { return }
        activeMembershipWrites.remove(id)
        mutationVersions[id, default: 0] += 1
        dirtyAttendees.insert(id)
        attendeeRevision += 1
    }

    private func applyWrite(_ game: Game) {
        var updated = game
        if muteTasks[game.id] != nil { updated.chatMuted = cache[game.id]?.chatMuted ?? game.chatMuted }
        if bookmarkTasks[game.id] != nil {
            updated.isBookmarked = savedIDs.contains(game.id)
            updated.spotAlert = spotAlertIDs.contains(game.id)
        }
        cache[game.id] = updated
        missingIDs.remove(game.id)
        lastAccess[game.id] = .now
    }

    // MARK: Hosting

    /// Throws so the form can show the error next to the fields.
    func createGame(_ draft: GameDraft) async throws {
        try requireAccount()
        guard !isCreatingGame else { throw DomainError.notAllowed }
        isCreatingGame = true
        let context = sessionID
        defer { if context == sessionID { isCreatingGame = false } }
        do {
            let game = try await games.createGame(draft)
            guard context == sessionID else { throw CancellationError() }
            applyWrite(game)
            mutationVersions[game.id, default: 0] += 1
            if !mapIDs.contains(game.id) { mapIDs.insert(game.id, at: 0) }
            lastCreatedID = game.id
            asksForNotificationPrimer = true
        } catch {
            guard context == sessionID, !OperationCancellation.isCancellation(error) else { throw CancellationError() }
            throw noteThrown(error)
        }
    }

    func updateGame(id: UUID, _ draft: GameDraft) async throws {
        try requireAccount()
        guard !activeHostingWrites.contains(id) else { throw DomainError.notAllowed }
        let context = sessionID
        let revision = privacyRevision
        activeHostingWrites.insert(id)
        mutationVersions[id, default: 0] += 1
        defer {
            if context == sessionID {
                activeHostingWrites.remove(id)
                mutationVersions[id, default: 0] += 1
            }
        }
        do {
            let updated = try await games.updateGame(id: id, draft)
            guard context == sessionID else { throw CancellationError() }
            guard revision == privacyRevision else {
                activeHostingWrites.remove(id)
                await loadGame(id)
                return
            }
            applyWrite(updated)
            activityByGame[id] = nil
        } catch {
            guard context == sessionID, !OperationCancellation.isCancellation(error) else { throw CancellationError() }
            throw noteThrown(error)
        }
    }

    /// Host sets "where to meet" (group chat). Uses `update_game` with everything else unchanged.
    func updateMeetPoint(_ id: UUID, to spot: String?) async throws {
        try requireAccount()
        guard let game = game(id) else { throw DomainError.notFound }
        var draft = GameDraft(game)
        draft.meetPoint = spot
        try await updateGame(id: id, draft)
        await loadActivity(id)
    }

    /// Soft cancel: the game stays visible to people going, marked cancelled.
    func cancelGame(_ id: UUID) async {
        guard !isGuest, !activeHostingWrites.contains(id) else { return }
        let context = sessionID
        let revision = privacyRevision
        activeHostingWrites.insert(id)
        mutationVersions[id, default: 0] += 1
        defer {
            if context == sessionID {
                activeHostingWrites.remove(id)
                mutationVersions[id, default: 0] += 1
            }
        }
        do {
            let updated = try await games.cancelGame(id: id)
            guard context == sessionID else { return }
            guard revision == privacyRevision else {
                activeHostingWrites.remove(id)
                await loadGame(id)
                return
            }
            applyWrite(updated)
            notice = String(localized: "Game cancelled. We let everyone going know.")
        } catch {
            guard context == sessionID, !OperationCancellation.isCancellation(error) else { return }
            fail(domainError(error))
        }
    }

    // MARK: Group chat

    /// "Before you chat": I agree. Throws so the sheet can stay open.
    func acceptChatRules() async throws {
        try requireAccount()
        let context = sessionID
        try await chat.acceptChatRules()
        guard context == sessionID else { throw CancellationError() }
        if profile?.chatRulesAcceptedAt == nil { profile?.chatRulesAcceptedAt = .now }
    }

    /// Stops or resumes chat alerts for a game you're in.
    /// - Parameters:
    ///   - id: The game.
    ///   - muted: True to stop them.
    func setChatMuted(_ id: UUID, muted: Bool) async {
        guard !isGuest, cache[id] != nil, let notifications else { return }
        let context = sessionID
        if muteTasks[id] == nil { confirmedMute[id] = cache[id]?.chatMuted ?? false }
        mutedGeneration[id, default: 0] += 1
        let generation = mutedGeneration[id] ?? 0
        cache[id]?.chatMuted = muted
        let prior = muteTasks[id]
        let task = Task { [self] in
            await prior?.value
            guard context == sessionID else { return }
            defer { if context == sessionID, mutedGeneration[id] == generation { muteTasks[id] = nil } }
            do {
                try await notifications.setChatMuted(gameID: id, muted: muted)
                guard context == sessionID else { return }
                confirmedMute[id] = muted
            } catch {
                guard context == sessionID, mutedGeneration[id] == generation else { return }
                cache[id]?.chatMuted = confirmedMute[id] ?? false
                if !OperationCancellation.isCancellation(error) { fail(domainError(error)) }
            }
        }
        muteTasks[id] = task
        await task.value
    }

    /// Opening a chat, or reading a message as it arrives, clears its count.
    func markChatRead(_ id: UUID) async {
        guard !isGuest else { return }
        let context = sessionID
        readAcknowledgementGeneration[id, default: 0] += 1
        unreadByGame[id] = nil
        pendingReadAcknowledgements.insert(id)
        if let existing = acknowledgementTasks[id] { await existing.value; return }
        let task = Task { @MainActor [self] in
            defer { if context == sessionID { acknowledgementTasks[id] = nil } }
            while context == sessionID, !Task.isCancelled {
                let generation = readAcknowledgementGeneration[id] ?? 0
                do {
                    try await acknowledgementReads.value(for: id) { [chat] in try await chat.markRead(gameID: id) }
                    guard context == sessionID, !Task.isCancelled else { return }
                    succeeded("acknowledgement")
                    // A message read after this RPC started needs its own acknowledgement.
                    // Sharing an earlier acknowledgement could leave that newer message unread.
                    if readAcknowledgementGeneration[id] == generation {
                        pendingReadAcknowledgements.remove(id)
                        return
                    }
                } catch {
                    guard context == sessionID else { return }
                    failedRead(error, resource: "acknowledgement")
                    return
                }
            }
        }
        acknowledgementTasks[id] = task
        await task.value
    }

    // MARK: Profile

    func updateProfile(_ input: ProfileInput) async throws {
        try requireAccount()
        let context = sessionID
        profileWriteGeneration += 1
        let version = profileWriteGeneration
        do {
            let updated = try await profiles.updateProfile(input)
            guard context == sessionID, version == profileWriteGeneration else { throw CancellationError() }
            profile = updated
            remember(campus: updated.university)
        } catch {
            guard context == sessionID, !OperationCancellation.isCancellation(error) else { throw CancellationError() }
            throw noteThrown(error)
        }
    }

    // MARK: Safety

    /// Throws so the sheet can stay open and offer a retry.
    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws {
        try requireAccount()
        let context = sessionID
        do { try await safety.report(target, reason: reason, note: note) }
        catch {
            guard context == sessionID, !OperationCancellation.isCancellation(error) else { throw CancellationError() }
            throw noteThrown(error)
        }
        guard context == sessionID else { throw CancellationError() }
    }

    /// Serialize opposing safety writes for each person, including their optimistic rollbacks.
    func block(_ person: PersonSummary) async { await changeBlock(person, blocked: true) }

    func unblock(_ person: PersonSummary) async { await changeBlock(person, blocked: false) }

    private func changeBlock(_ person: PersonSummary, blocked: Bool) async {
        guard !isGuest, person.id != profile?.id else { return }
        let context = sessionID
        while let pending = safetyTasks[person.id] {
            await pending.value
            guard context == sessionID, !Task.isCancelled else { return }
        }
        guard blockedIDs.contains(person.id) != blocked else { return }
        safetyGeneration += 1
        let revisionBefore = privacyRevision
        let index = blockedPeople.firstIndex { $0.id == person.id } ?? 0
        if blocked { blockedPeople.insert(person, at: 0) }
        else { blockedPeople.removeAll { $0.id == person.id } }
        let attendeesWithThem = Array(attendeesByGame.filter { $0.value.contains { $0.id == person.id } }.keys)
        let blockedFlagsBefore = Dictionary(uniqueKeysWithValues: attendeesWithThem.map { ($0, cache[$0]?.hasBlockedAttendee ?? false) })
        if blocked { for id in attendeesWithThem { cache[id]?.hasBlockedAttendee = true } }
        let task = Task { @MainActor [self] in
            defer { if context == sessionID { safetyTasks[person.id] = nil } }
            guard context == sessionID, !isGuest else { return }
            do {
                if blocked { try await safety.block(userID: person.id) }
                else { try await safety.unblock(userID: person.id) }
                guard context == sessionID else { return }
                await refresh()
            } catch {
                guard context == sessionID else { return }
                if blocked { blockedPeople.removeAll { $0.id == person.id } }
                else { blockedPeople.insert(person, at: min(index, blockedPeople.count)) }
                if revisionBefore == privacyRevision {
                    for id in attendeesWithThem {
                        cache[id]?.hasBlockedAttendee = (blockedFlagsBefore[id] ?? false)
                            || (attendeesByGame[id] ?? []).contains { blockedIDs.contains($0.id) }
                    }
                }
                if !OperationCancellation.isCancellation(error) { fail(domainError(error)) }
            }
        }
        safetyTasks[person.id] = task
        await task.value
    }

    // MARK: Saved (on the phone, N15)

    func toggleSaved(_ id: UUID) {
        guard !isGuest else { return }
        let saved = !savedIDs.contains(id)
        rememberBookmarkState(id)
        savedGeneration[id, default: 0] += 1
        let generation = savedGeneration[id] ?? 0
        if saved {
            savedIDs.insert(id)
            notice = String(localized: "Saved. Find it under bookmarks.")
        } else {
            savedIDs.remove(id)
            spotAlertIDs.remove(id)
            write(spotAlertIDs, forKey: spotAlertKey)
        }
        write(savedIDs, forKey: savedKey)
        queueBookmarkWrite(id, mutation: .saved(saved), generation: generation)
    }

    /// "Alert me if a spot opens" on a full game. Turning it on saves the game too, so it's in
    /// Saved games. The server sends the push. If that write fails, the switch goes back.
    func toggleSpotAlert(_ id: UUID) {
        guard !isGuest else { return }
        let on = !spotAlertIDs.contains(id)
        rememberBookmarkState(id)
        savedGeneration[id, default: 0] += 1
        let generation = savedGeneration[id] ?? 0
        if on {
            spotAlertIDs.insert(id)
            savedIDs.insert(id)
            write(savedIDs, forKey: savedKey)
        } else {
            spotAlertIDs.remove(id)
        }
        write(spotAlertIDs, forKey: spotAlertKey)
        queueBookmarkWrite(id, mutation: .alert(on), generation: generation)
    }

    /// "Remove" on a cancelled game in Going. The game is still cancelled on the server; this
    /// only stops listing it here.
    func dismissCancelled(_ id: UUID) {
        guard !isGuest else { return }
        dismissedIDs.insert(id)
        write(dismissedIDs, forKey: dismissedKey)
    }

    /// Only the signed-in account's campus is kept here; a guest's never is (`loadGuest`).
    private static let campusKey = "lastCampus"

    /// The campus from the last signed-in launch, if any.
    private var rememberedCampus: University? {
        defaults.data(forKey: Self.campusKey).flatMap { try? JSONDecoder().decode(University.self, from: $0) }
    }

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

    /// One upload of the saves that only lived on this phone. A failure leaves them to try next launch.
    private func importBookmarksIfNeeded() async {
        let key = "bookmarksImported.\(accountKey)"
        guard !defaults.bool(forKey: key) else { return }
        guard !savedIDs.isEmpty || !spotAlertIDs.isEmpty else {
            defaults.set(true, forKey: key)
            return
        }
        let context = sessionID
        do {
            try await games.importBookmarks(ids: Array(savedIDs), alertIDs: Array(spotAlertIDs))
            guard context == sessionID else { return }
            defaults.set(true, forKey: key)
        } catch {
            guard context == sessionID else { return }
            failedRead(error, resource: "saved")
        }
    }

    private enum BookmarkMutation {
        case saved(Bool), alert(Bool)
    }

    private func rememberBookmarkState(_ id: UUID) {
        if bookmarkTasks[id] == nil {
            confirmedBookmarks[id] = (savedIDs.contains(id), spotAlertIDs.contains(id))
        }
    }

    /// Bookmark and alert writes share one queue because they mutate the same server row.
    private func queueBookmarkWrite(_ id: UUID, mutation: BookmarkMutation, generation: Int) {
        let prior = bookmarkTasks[id]
        let session = bookmarkSession
        bookmarkTasks[id] = Task {
            await prior?.value
            guard self.bookmarkSession == session else { return }
            defer {
                if self.bookmarkSession == session, self.savedGeneration[id] == generation {
                    self.bookmarkTasks[id] = nil
                }
            }
            let revision = self.privacyRevision
            do {
                let game: Game
                switch mutation {
                case .saved(let on): game = try await self.games.setBookmark(id: id, on: on)
                case .alert(let on): game = try await self.games.setSpotAlert(id: id, on: on)
                }
                guard self.bookmarkSession == session else { return }
                self.confirmedBookmarks[id] = (game.isBookmarked, game.spotAlert)
                guard self.savedGeneration[id] == generation else { return }
                self.applyBookmark(game, publishGame: revision == self.privacyRevision)
                if revision != self.privacyRevision { await self.loadGame(id) }
            } catch {
                guard self.bookmarkSession == session, self.savedGeneration[id] == generation else { return }
                let state = self.confirmedBookmarks[id] ?? (saved: false, alert: false)
                if state.saved { self.savedIDs.insert(id) } else { self.savedIDs.remove(id) }
                if state.alert { self.spotAlertIDs.insert(id) } else { self.spotAlertIDs.remove(id) }
                self.write(self.savedIDs, forKey: self.savedKey)
                self.write(self.spotAlertIDs, forKey: self.spotAlertKey)
                self.fail(self.domainError(error))
            }
        }
    }

    /// Waits for the writes already queued by the UI (also useful to await final server state).
    func waitForBookmarkWrites() async {
        let tasks = Array(bookmarkTasks.values)
        for task in tasks { await task.value }
    }

    /// The bookmark RPCs can add or remove, unlike a map refresh, which only adds.
    private func applyBookmark(_ game: Game, publishGame: Bool = true) {
        if game.isBookmarked {
            savedIDs.insert(game.id)
        } else {
            savedIDs.remove(game.id)
            spotAlertIDs.remove(game.id)
        }
        if game.spotAlert {
            spotAlertIDs.insert(game.id)
            savedIDs.insert(game.id)
        } else {
            spotAlertIDs.remove(game.id)
        }
        if publishGame {
            noteSpotOpened(replacing: cache[game.id], with: game)
            cache[game.id] = game
        }
        write(savedIDs, forKey: savedKey)
        write(spotAlertIDs, forKey: spotAlertKey)
    }

    // MARK: Sign-out

    /// Clears everything held for this account, and ends guest mode. Saved games stay on the phone, by account.
    func reset() {
        clearSession()
        campus = nil
        defaults.removeObject(forKey: Self.campusKey)
    }

    /// Drops every game, list and listener held in memory, so the next load starts clean. Leaves
    /// the campus alone: `reset()`, `load()` and `loadGuest` each decide what it should be.
    private func clearSession() {
        sessionID = UUID()
        listReads.cancelAll()
        gameReads.cancelAll()
        attendeeReads.cancelAll()
        activityReads.cancelAll()
        profileReads.cancelAll()
        inviteReads.cancelAll()
        peopleReads.cancelAll()
        catalogReads.cancelAll()
        unreadReads.cancelAll()
        acknowledgementReads.cancelAll()
        for task in acknowledgementTasks.values { task.cancel() }
        acknowledgementTasks = [:]
        sessionLoads.cancelAll()
        for task in safetyTasks.values { task.cancel() }
        safetyTasks = [:]
        for task in membershipTasks.values { task.cancel() }
        for task in muteTasks.values { task.cancel() }
        membershipTasks = [:]
        muteTasks = [:]
        activeMembershipWrites = []
        activeHostingWrites = []
        isCreatingGame = false
        mutedGeneration = [:]
        confirmedMute = [:]
        mutationVersions = [:]
        publishedEpoch = [:]
        retainedGameIDs = []
        lastAccess = [:]
        profileWriteGeneration += 1
        safetyGeneration += 1
        privacyRevision += 1
        pendingReadAcknowledgements = []
        readAcknowledgementGeneration = [:]
        attendeeDates = [:]
        dirtyAttendees = []
        attendeeRevision += 1
        isGuest = false
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
        spentSpotAlerts = []
        bookmarkSession = UUID()
        for task in bookmarkTasks.values { task.cancel() }
        bookmarkTasks = [:]
        confirmedBookmarks = [:]
        savedGeneration = [:]
        dismissedIDs = []
        unreadByGame = [:]
        blockedPeople = []
        invites = []
        hasAskedForBetaBadge = false
        profile = nil
        lastCreatedID = nil
        asksForNotificationPrimer = false
        notificationPrimerAccepted = false
        mapState = .idle
        myGamesState = .idle
        offlineResources = []
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

    /// A failed load or action: track offline and session problems, without a toast. A guest has
    /// no session to lose, so their failures never send the app back to sign-in.
    func noteFailure(_ error: DomainError, resource: String = "general") {
        if error == .offline { offlineResources.insert(resource) }
        if !isGuest, error == .suspended || error == .notAuthenticated { onSessionProblem?() }
    }

    /// Guests can't write: the screens ask them to sign in first, so this is only a backstop. It
    /// isn't a session problem, so it isn't reported as one.
    /// - Throws: `DomainError.notAuthenticated` in guest mode.
    private func requireAccount() throws {
        if isGuest { throw DomainError.notAuthenticated }
    }

    private func noteThrown(_ error: any Error) -> DomainError {
        let error = domainError(error)
        noteFailure(error)
        return error
    }
}
