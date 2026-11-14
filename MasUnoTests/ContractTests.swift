import Foundation
import Testing
@testable import masUNO

/// The E1 contract: error codes, model rules and the mock backend's RPC behavior.
/// If a test here changes, `docs/API.md` probably should too.
@MainActor
struct DomainModelTests {
    @Test(arguments: [
        ("full", DomainError.full), ("cancelled", .cancelled), ("ended", .ended), ("blocked", .blocked),
        ("not_found", .notFound), ("not_allowed", .notAllowed), ("limit_reached", .limitReached),
        ("capacity_below_going", .capacityBelowGoing), ("invalid_time", .invalidTime),
        ("invalid_text", .invalidText), ("invalid_input", .invalidInput),
        ("not_authenticated", .notAuthenticated), ("suspended", .suspended),
        ("email_not_allowed", .emailNotAllowed),
        ("pending_approval", .pendingApproval),
    ])
    func serverCodesMap(code: String, error: DomainError) {
        #expect(DomainError(serverCode: code) == error)
        #expect(!error.message.isEmpty)
    }

    @Test func unknownCodeIsKept() {
        #expect(DomainError(serverCode: "brand_new") == .unknown("brand_new"))
    }

    @Test func builtInActivitiesAreTheFiveSports() {
        #expect(Activity.builtIn.map(\.slug) == ["basketball", "tennis", "soccer", "volleyball", "padel"])
    }

    @Test func namesShowAsFirstNameLastInitial() {
        #expect(MockFixtures.alex.displayName == "Alex R.")
        #expect(MockFixtures.alex.initials == "AR")
    }

    @Test func fixturesCoverEveryDetailState() async throws {
        let backend = MockBackend()
        let expected: [(UUID, GameStatus)] = [
            (MockFixtures.GameID.open, .open), (MockFixtures.GameID.full, .full),
            (MockFixtures.GameID.going, .going), (MockFixtures.GameID.hosting, .hosting),
            (MockFixtures.GameID.ended, .ended), (MockFixtures.GameID.cancelled, .cancelled),
        ]
        for (id, status) in expected {
            let game = try await backend.fetchGame(id: id)
            #expect(game.status(now: backend.now) == status)
        }
    }

    @Test func bumpLastsTwoHours() async throws {
        let backend = MockBackend()
        let game = try await backend.fetchGame(id: MockFixtures.GameID.bumped)
        #expect(game.isBumped(now: backend.now))
        #expect(!game.isBumped(now: backend.now.addingTimeInterval(2 * 3600)))
    }
}

@MainActor
struct MockGameRulesTests {
    let backend = MockBackend()

    private func draft(
        title: String = "Evening hoops", minutes: Double = 120, capacity: Int = 6, meetPoint: String? = nil
    ) -> GameDraft {
        GameDraft(
            activity: MockFixtures.activity("basketball"), title: title,
            startsAt: backend.now.addingTimeInterval(minutes * 60), durationMinutes: 60,
            capacity: capacity, place: MockFixtures.Places.basketballCourts, meetPoint: meetPoint
        )
    }

    @Test func mapHidesCancelledEndedAndFull() async throws {
        let ids = try await backend.fetchMapGames().map(\.id)
        #expect(ids.contains(MockFixtures.GameID.open))
        #expect(!ids.contains(MockFixtures.GameID.full))
        #expect(!ids.contains(MockFixtures.GameID.ended))
        #expect(!ids.contains(MockFixtures.GameID.cancelled))
        #expect(ids.first == MockFixtures.GameID.bumped)
    }

    @Test func joinTakesASpotAndIsIdempotent() async throws {
        let joined = try await backend.joinGame(id: MockFixtures.GameID.open)
        #expect(joined.myRole == .player)
        #expect(joined.goingCount == 3)
        let again = try await backend.joinGame(id: MockFixtures.GameID.open)
        #expect(again.goingCount == 3)
    }

    @Test func losingTheLastSpotRaceIsFull() async throws {
        backend.fillGame(id: MockFixtures.GameID.lastSpot)
        await #expect(throws: DomainError.full) {
            try await backend.joinGame(id: MockFixtures.GameID.lastSpot)
        }
    }

    @Test func joinRejectsCancelledAndEnded() async throws {
        await #expect(throws: DomainError.cancelled) { try await backend.joinGame(id: MockFixtures.GameID.cancelled) }
        await #expect(throws: DomainError.notFound) { try await backend.joinGame(id: UUID()) }
        backend.now = backend.now.addingTimeInterval(24 * 3600)
        await #expect(throws: DomainError.ended) { try await backend.joinGame(id: MockFixtures.GameID.open) }
    }

    @Test func hostJoiningOwnGameIsANoOp() async throws {
        let game = try await backend.joinGame(id: MockFixtures.GameID.hosting)
        #expect(game.myRole == .host)
        #expect(game.goingCount == 3)
    }

    @Test func leavingAFullGameBumpsIt() async throws {
        let id = MockFixtures.GameID.lastSpot
        _ = try await backend.joinGame(id: id)
        let left = try await backend.leaveGame(id: id)
        #expect(left.goingCount == 3)
        #expect(left.repostedAt == backend.now)
    }

    @Test func leavingWithSpotsLeftDoesNotBump() async throws {
        let left = try await backend.leaveGame(id: MockFixtures.GameID.going)
        #expect(left.repostedAt == nil)
    }

    @Test func hostCannotLeave() async throws {
        await #expect(throws: DomainError.notAllowed) { try await backend.leaveGame(id: MockFixtures.GameID.hosting) }
    }

    @Test func createEnforcesFormRules() async throws {
        await #expect(throws: DomainError.invalidInput) { try await backend.createGame(draft(title: "  ")) }
        await #expect(throws: DomainError.invalidInput) { try await backend.createGame(draft(capacity: 23)) }
        await #expect(throws: DomainError.invalidText) { try await backend.createGame(draft(title: "pinche game")) }
        await #expect(throws: DomainError.invalidTime) { try await backend.createGame(draft(minutes: -5)) }
        await #expect(throws: DomainError.invalidTime) { try await backend.createGame(draft(minutes: 7 * 24 * 60)) }
    }

    @Test func hostingLimitIsThreeUpcoming() async throws {
        // The fixtures already host one upcoming game.
        _ = try await backend.createGame(draft())
        _ = try await backend.createGame(draft())
        await #expect(throws: DomainError.limitReached) { try await backend.createGame(draft()) }
    }

    @Test func updateIsHostOnlyAndKeepsPlayersAboveGoing() async throws {
        let theirs = try await backend.fetchGame(id: MockFixtures.GameID.open)
        await #expect(throws: DomainError.notAllowed) { try await backend.updateGame(id: theirs.id, GameDraft(theirs)) }

        var mine = GameDraft(try await backend.fetchGame(id: MockFixtures.GameID.hosting))
        mine.capacity = 2
        await #expect(throws: DomainError.capacityBelowGoing) {
            try await backend.updateGame(id: MockFixtures.GameID.hosting, mine)
        }
    }

    @Test func raisingCapacityOnAFullGameBumpsIt() async throws {
        let id = MockFixtures.GameID.hosting
        backend.fillGame(id: id)
        var edit = GameDraft(try await backend.fetchGame(id: id))
        edit.capacity = 12
        let updated = try await backend.updateGame(id: id, edit)
        #expect(updated.repostedAt == backend.now)
    }

    /// A host can fix the meet-up spot once the game has started; the time isn't re-checked.
    @Test func meetUpEditWorksDuringAGame() async throws {
        let id = MockFixtures.GameID.hosting
        var edit = GameDraft(try await backend.fetchGame(id: id))
        backend.now = edit.startsAt.addingTimeInterval(600)
        edit.meetPoint = "South gate"
        let updated = try await backend.updateGame(id: id, edit)
        #expect(updated.meetPoint == "South gate")
        #expect(updated.materialChangeAt == backend.now)
    }

    @Test func cancelIsSoftAndIdempotent() async throws {
        let id = MockFixtures.GameID.hosting
        let cancelled = try await backend.cancelGame(id: id)
        #expect(cancelled.status(now: backend.now) == .cancelled)
        _ = try await backend.cancelGame(id: id)
        #expect(try await backend.fetchGame(id: id).isCancelled)
    }

    @Test func activityLogKeepsPeopleWhoLeft() async throws {
        let id = MockFixtures.GameID.open
        _ = try await backend.joinGame(id: id)
        _ = try await backend.leaveGame(id: id)
        let kinds = try await backend.fetchActivity(gameID: id).map(\.kind)
        #expect(kinds.suffix(2) == [.joined, .left])
    }

    @Test func nextErrorSimulatesOffline() async throws {
        backend.nextError = .offline
        await #expect(throws: DomainError.offline) { try await backend.fetchMapGames() }
        #expect(try await backend.fetchMapGames().isEmpty == false)
    }
}

@MainActor
struct MockSafetyTests {
    let backend = MockBackend()

    @Test func blockHidesGamesAndNames() async throws {
        try await backend.block(userID: MockFixtures.alex.id)
        let ids = try await backend.fetchMapGames().map(\.id)
        #expect(!ids.contains(MockFixtures.GameID.open))
        await #expect(throws: DomainError.notFound) { try await backend.fetchGame(id: MockFixtures.GameID.open) }

        let who = try await backend.fetchAttendees(gameID: MockFixtures.GameID.hosting)
        #expect(!who.map(\.id).contains(MockFixtures.alex.id))
        // The count still includes them (C9).
        #expect(try await backend.fetchGame(id: MockFixtures.GameID.hosting).goingCount == 3)
    }

    @Test func joiningAGameWithSomeoneBlockedFails() async throws {
        try await backend.block(userID: MockFixtures.ricardo.id)
        let game = try await backend.fetchGame(id: MockFixtures.GameID.open)
        #expect(game.hasBlockedAttendee)
        await #expect(throws: DomainError.blocked) { try await backend.joinGame(id: game.id) }
    }

    /// Settings › Blocked people must still show names RLS hides everywhere else.
    @Test func blockedPeopleListsNamesAndUnblockRestores() async throws {
        try await backend.block(userID: MockFixtures.alex.id)
        try await backend.block(userID: MockFixtures.priya.id)
        #expect(try await backend.fetchBlockedPeople().map(\.firstName) == ["Priya", "Alex"])

        try await backend.unblock(userID: MockFixtures.alex.id)
        #expect(try await backend.fetchMapGames().map(\.id).contains(MockFixtures.GameID.open))
    }

    /// `guest_games` has no viewer, so a block doesn't change it, and it never names anyone.
    @Test func guestGamesIgnoreBlocksAndHideNames() async throws {
        try await backend.block(userID: MockFixtures.alex.id)
        backend.endSession(expired: false)
        let guest = try await backend.fetchGuestGames(campus: MockFixtures.tec.id)
        #expect(guest.contains { $0.id == MockFixtures.GameID.open })
        #expect(guest.allSatisfy { $0.host.isHidden && $0.notes == nil && $0.meetPoint == nil })
        #expect(try await backend.fetchGuestGames(campus: MockFixtures.otherCampus.id).isEmpty)
    }

    @Test func cannotBlockYourself() async throws {
        await #expect(throws: DomainError.invalidInput) { try await backend.block(userID: backend.me.id) }
    }

    @Test func reportsAreRecorded() async throws {
        try await backend.report(.game(MockFixtures.GameID.open), reason: .spam, note: nil)
        #expect(backend.reports.count == 1)
    }
}

@MainActor
struct MockAuthTests {
    private let input = ProfileInput(
        firstName: "Emilio", lastName: "Garza", gradYear: 2029, interests: [MockFixtures.activity("padel")]
    )

    @Test func newStudentWalksThroughOnboarding() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        try await auth.signIn(at: MockFixtures.tec)
        #expect(auth.state == .needsProfile)
        try await auth.completeProfile(input)
        #expect(auth.state == .needsGuidelines)
        try await auth.acceptGuidelines()
        #expect(auth.state == .signedIn(userID: auth.me.id))
        #expect(try await auth.fetchMyProfile()?.summary.displayName == "Emilio G.")
    }

    @Test func closingTheWebSheetIsNotAFailure() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.cancelsNextSignIn = true
        try await auth.signIn(at: MockFixtures.tec)
        #expect(auth.state == .signedOut(expired: false))
    }

    /// The hook checks the account that signed in, not the school picked in the app.
    @Test func otherDomainsAreRefused() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.schoolAccountEmail = "someone@gmail.com"
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signIn(at: MockFixtures.tec) }
        #expect(auth.state == .signedOut(expired: false))
    }

    /// N36: a school address signs up with a password and waits for the team.
    @Test func passwordSignUpWaitsForApproval() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signUp(email: "someone@gmail.com", password: "long-enough") }
        #expect(auth.state == .signedOut(expired: false))

        try await auth.signUp(email: "A0123@tec.mx", password: "long-enough")
        #expect(auth.state == .pendingApproval)
        await #expect(throws: DomainError.pendingApproval) { try await auth.completeProfile(input) }
        await #expect(throws: DomainError.emailTaken) { try await auth.signUp(email: "a0123@tec.mx", password: "another-one") }

        // Still waiting after signing out and back in.
        try await auth.signOut()
        await #expect(throws: DomainError.invalidCredentials) { try await auth.signIn(email: "a0123@tec.mx", password: "wrong") }
        try await auth.signIn(email: "a0123@tec.mx", password: "long-enough")
        #expect(auth.state == .pendingApproval)
        try await auth.refreshStatus()
        #expect(auth.state == .pendingApproval)

        auth.approveSignUp()
        try await auth.refreshStatus()
        #expect(auth.state == .needsProfile)
        try await auth.completeProfile(input)
        try await auth.acceptGuidelines()
        try await auth.signOut()
        try await auth.signIn(email: "a0123@tec.mx", password: "long-enough")
        #expect(auth.state == .signedIn(userID: auth.me.id))
    }

    @Test func reviewAccountUsesAPassword() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        await #expect(throws: DomainError.invalidCredentials) {
            try await auth.signIn(email: MockFixtures.reviewEmail, password: "nope")
        }
        await #expect(throws: DomainError.invalidCredentials) {
            try await auth.signIn(email: "a0123@tec.mx", password: MockFixtures.reviewPassword)
        }
        try await auth.signIn(email: MockFixtures.reviewEmail, password: MockFixtures.reviewPassword)
        #expect(auth.state == .signedIn(userID: auth.me.id))
    }

    @Test func profileNeedsAnInterestAndFriendlyNames() async throws {
        let auth = MockBackend(state: .needsProfile)
        var noSports = input
        noSports.interests = []
        await #expect(throws: DomainError.invalidInput) { try await auth.completeProfile(noSports) }
        var rude = input
        rude.firstName = "Pendejo"
        await #expect(throws: DomainError.invalidText) { try await auth.completeProfile(rude) }
    }

    @Test func suspendedAccountsCannotWrite() async throws {
        let auth = MockBackend()
        auth.suspend()
        #expect(auth.state == .suspended)
        await #expect(throws: DomainError.suspended) { try await auth.joinGame(id: MockFixtures.GameID.open) }
    }

    @Test func expiredSessionIsTold() async throws {
        let auth = MockBackend()
        auth.endSession(expired: true)
        #expect(auth.state == .signedOut(expired: true))
        await #expect(throws: DomainError.notAuthenticated) { try await auth.joinGame(id: MockFixtures.GameID.open) }
    }

    @Test func deleteAccountRemovesHostedAndFreesJoined() async throws {
        let auth = MockBackend()
        try await auth.deleteAccount()
        #expect(auth.state == .signedOut(expired: false))
        #expect(!auth.games.contains { $0.id == MockFixtures.GameID.hosting })
        #expect(!auth.games.contains { $0.host.id == auth.me.id })
        #expect(auth.games.first { $0.id == MockFixtures.GameID.going }?.goingCount == 4)
        #expect(auth.profile == nil)
    }
}

@MainActor
struct CampusTests {
    @Test func mapFallbackIsFifteenKilometersFromYourCampus() {
        let tec = MockFixtures.tec
        #expect(tec.isNearby(tec.center))
        #expect(tec.isNearby(.init(latitude: 25.72, longitude: -100.31))) // north Monterrey, ~8 km
        #expect(!tec.isNearby(.init(latitude: 37.33, longitude: -122.01))) // Cupertino: App Review
    }

    @Test func launchCampusIsData() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.schoolAccountEmail = "a@uanl.edu.mx"
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signIn(at: MockFixtures.otherCampus) }

        // Tec doesn't work out: the campus changes on the server, with no app change.
        var closedTec = MockFixtures.tec
        closedTec.signupEnabled = false
        auth.universities = [MockFixtures.otherCampus, closedTec]
        auth.schoolAccountEmail = "a0123@tec.mx"
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signIn(at: closedTec) }

        auth.schoolAccountEmail = "a@uanl.edu.mx"
        try await auth.signIn(at: MockFixtures.otherCampus)
        try await auth.completeProfile(ProfileInput(
            firstName: "Ana", lastName: "Solis", gradYear: 2028, interests: [MockFixtures.activity("soccer")]
        ))
        #expect(try await auth.fetchMyProfile()?.university == MockFixtures.otherCampus)
    }

    /// Closing a campus stops new sign-ups, not the people already there: the hook only runs for new users.
    @Test func existingAccountsSurviveTheirCampusClosing() async throws {
        let auth = MockBackend()
        var closedTec = MockFixtures.tec
        closedTec.signupEnabled = false
        auth.universities = [MockFixtures.otherCampus, closedTec]
        auth.endSession(expired: true)

        try await auth.signIn(at: closedTec)
        #expect(auth.state == .signedIn(userID: auth.me.id))
        #expect(try await auth.fetchMyProfile()?.university == MockFixtures.tec)
    }

    @Test func domainMatchIsExact() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        for email in ["a@mail.tec.mx", "tec.mx"] {
            auth.schoolAccountEmail = email
            await #expect(throws: DomainError.emailNotAllowed) { try await auth.signIn(at: MockFixtures.tec) }
        }
    }

    @Test func reviewAccountLandsOnTheDemoCampus() async throws {
        let auth = MockBackend(state: .signedOut(expired: false))
        try await auth.signIn(email: MockFixtures.reviewEmail, password: MockFixtures.reviewPassword)
        #expect(try await auth.fetchMyProfile()?.university == MockFixtures.demoCampus)
        #expect(try await auth.fetchUniversities() == [MockFixtures.tec])
    }

    @Test func onboardingCopyFollowsTheCampus() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.schoolAccountEmail = "someone@gmail.com"
        let other = OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.otherCampus)
        other.selectedSchool = MockFixtures.otherCampus
        await other.continueWithSchool()
        #expect(other.signInError == "masUNO is just for UANL students right now. Use your UANL school account.")

        let generic = OnboardingViewModel(auth: auth, catalog: auth)
        generic.selectedSchool = MockFixtures.tec
        await generic.continueWithSchool()
        #expect(generic.signInError == "masUNO isn't open at your school yet.")
    }

    @Test func storeRemembersTheCampusForOfflineLaunches() async {
        let backend = MockBackend()
        let defaults = UserDefaults(suiteName: "CampusTests.\(UUID().uuidString)")!
        let first = GameStore(games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults)
        await first.load()
        #expect(first.campus == MockFixtures.tec)

        let offline = GameStore(games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults)
        #expect(offline.campus == MockFixtures.tec)

        offline.reset()
        let afterSignOut = GameStore(games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults)
        #expect(afterSignOut.campus == nil)
    }
}

@MainActor
struct GuestBrowsingTests {
    /// The guest choice is kept in defaults, so each test gets its own.
    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GuestBrowsingTests.app.\(UUID().uuidString)")!
    }

    private func store(_ backend: MockBackend) -> GameStore {
        GameStore(games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
                  defaults: Self.freshDefaults())
    }

    @Test func aGuestWhoComesBackLandsOnTheMapAgain() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let defaults = Self.freshDefaults()
        let first = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        await first.browseAsGuest(campus: MockFixtures.tec, store: store(auth))

        let relaunched = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        let fresh = store(auth)
        await relaunched.start()
        #expect(relaunched.session == .guest)
        await relaunched.resumeGuestBrowsing(store: fresh)
        #expect(fresh.isGuest)
        #expect(!fresh.mapGames().isEmpty)
    }

    @Test func goingToSignUpOrSigningInForgetsTheGuestChoice() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let defaults = Self.freshDefaults()
        let app = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        let games = store(auth)
        await app.browseAsGuest(campus: MockFixtures.tec, store: games)
        app.endGuestBrowsing(resume: .signUp, store: games)
        #expect(AppViewModel(auth: auth, catalog: auth, defaults: defaults).session == .onboarding)

        // A guest choice left behind never outranks an account.
        await app.browseAsGuest(campus: MockFixtures.tec, store: games)
        let signedIn = MockBackend()
        let relaunched = AppViewModel(auth: signedIn, catalog: signedIn, defaults: defaults)
        await relaunched.start()
        #expect(relaunched.session == .signedIn)
        #expect(!relaunched.isBrowsingAsGuest)
    }

    @Test func aGuestWhoseCampusClosedStartsAtWelcome() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let defaults = Self.freshDefaults()
        await AppViewModel(auth: auth, catalog: auth, defaults: defaults).browseAsGuest(campus: MockFixtures.tec, store: store(auth))

        var closed = MockFixtures.tec
        closed.signupEnabled = false
        auth.universities = [closed]
        let relaunched = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        await relaunched.start()
        #expect(relaunched.session == .onboarding)
    }

    @Test func aGuestSeesBlankCirclesNotACount() {
        let world = MockFixtures.world(now: .now)
        var game = world.games[0]
        game.host = .hidden
        let lineup = Lineup(game: game, attendees: [], me: nil)
        #expect(lineup.people.isEmpty)
        #expect(lineup.unlisted == game.goingCount)
        #expect(lineup.accessibilityLabel.contains("\(game.goingCount) going"))
    }

    @Test func browseAsGuestShowsTheMapSession() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        let store = GameStore(games: auth, profiles: auth, safety: auth, chat: auth, catalog: auth,
                              defaults: UserDefaults(suiteName: "GuestBrowsingTests.\(UUID().uuidString)")!)
        #expect(app.session == .onboarding)
        await app.browseAsGuest(campus: MockFixtures.tec, store: store)
        #expect(app.session == .guest)
        #expect(store.isGuest)
        let games = store.mapGames()
        #expect(!games.isEmpty)
        #expect(games.allSatisfy { $0.hidesPeople })
    }

    @Test func endingGuestBrowseOpensSignUpOrSignIn() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        let store = GameStore(games: auth, profiles: auth, safety: auth, chat: auth, catalog: auth,
                              defaults: UserDefaults(suiteName: "GuestBrowsingEnd.\(UUID().uuidString)")!)
        await app.browseAsGuest(campus: MockFixtures.tec, store: store)
        app.requireAccount(.join)
        #expect(app.accountPrompt == .join)
        app.endGuestBrowsing(resume: .signUp, store: store)
        #expect(app.session == .onboarding)
        #expect(app.onboardingResume == .signUp)
        #expect(!store.isGuest)
        #expect(app.accountPrompt == nil)

        let onboarding = OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.tec)
        onboarding.applyResume(.signIn)
        #expect(onboarding.path == [.signIn])
    }

    @Test func welcomeBrowseAsGuestUsesTheLaunchCampus() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        let store = GameStore(games: auth, profiles: auth, safety: auth, chat: auth, catalog: auth,
                              defaults: UserDefaults(suiteName: "GuestWelcome.\(UUID().uuidString)")!)
        let onboarding = OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.tec)
        await onboarding.browseAsGuest(app: app, store: store)
        #expect(app.session == .guest)
        #expect(onboarding.guestBrowseError == nil)
    }

    @Test func severalOpenCampusesAskWhichOne() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.universities = [MockFixtures.tec, MockFixtures.otherCampus]
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        let games = store(auth)
        let onboarding = OnboardingViewModel(auth: auth, catalog: auth)
        await onboarding.browseAsGuest(app: app, store: games)
        #expect(onboarding.path == [.guestCampus])
        #expect(app.session == .onboarding)
        #expect(onboarding.guestBrowseError == nil)

        await onboarding.loadSchools()
        onboarding.guestCampusChoice = MockFixtures.otherCampus
        await onboarding.startGuestBrowsing(app: app, store: games)
        #expect(app.session == .guest)
        #expect(app.guestCampus?.id == MockFixtures.otherCampus.id)
        #expect(games.campus?.id == MockFixtures.otherCampus.id)
    }

    @Test func oneOpenCampusGoesStraightIn() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        let onboarding = OnboardingViewModel(auth: auth, catalog: auth)
        await onboarding.browseAsGuest(app: app, store: store(auth))
        #expect(onboarding.path.isEmpty)
        #expect(app.guestCampus?.id == MockFixtures.tec.id)
    }

    @Test func browsingAnotherCampusEndsTheGuestSessionAndAsksAgain() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.universities = [MockFixtures.tec, MockFixtures.otherCampus]
        let defaults = Self.freshDefaults()
        let app = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        let games = store(auth)
        await app.start()
        #expect(app.canSwitchGuestCampus)
        await app.browseAsGuest(campus: MockFixtures.tec, store: games)

        app.endGuestBrowsing(resume: .guestCampus, store: games)
        #expect(app.session == .onboarding)
        #expect(!games.isGuest)
        #expect(app.onboardingResume == .guestCampus)

        let onboarding = OnboardingViewModel(auth: auth, catalog: auth)
        onboarding.applyResume(.guestCampus)
        #expect(onboarding.path == [.guestCampus])
    }

    @Test func oneOpenCampusOffersNoSwitch() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: auth, catalog: auth, defaults: Self.freshDefaults())
        await app.start()
        #expect(!app.canSwitchGuestCampus)
    }

    @Test func aRelaunchRestoresTheChosenCampus() async {
        let auth = MockBackend(state: .signedOut(expired: false))
        auth.universities = [MockFixtures.tec, MockFixtures.otherCampus]
        let defaults = Self.freshDefaults()
        await AppViewModel(auth: auth, catalog: auth, defaults: defaults)
            .browseAsGuest(campus: MockFixtures.otherCampus, store: store(auth))

        let relaunched = AppViewModel(auth: auth, catalog: auth, defaults: defaults)
        await relaunched.start()
        #expect(relaunched.session == .guest)
        #expect(relaunched.guestCampus?.id == MockFixtures.otherCampus.id)
    }
}

@MainActor
struct OnboardingFlowTests {
    private func model(_ state: AuthState = .signedOut(expired: false)) -> (OnboardingViewModel, MockBackend) {
        let auth = MockBackend(state: state)
        return (OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.tec), auth)
    }

    @Test func newStudentGoesThroughQuickCheckSchoolAndVerified() async {
        let (model, auth) = model()
        #expect(model.path.isEmpty)
        model.getStarted()
        #expect(model.isSignInSheetPresented)
        model.findMySchool()
        #expect(!model.isSignInSheetPresented)
        #expect(model.path == [.findSchool])

        await model.loadSchools()
        #expect(model.selectedSchool == MockFixtures.tec)
        await model.continueWithSchool()
        #expect(auth.state == .needsProfile)
        #expect(model.path == [.findSchool, .verified])
        #expect(model.firstName == "Emilio")
        #expect(model.lastName == "Garza")
    }

    @Test func oneSchoolIsPickedForYouButSeveralAreNot() async {
        let (model, auth) = model()
        auth.universities = [MockFixtures.tec, MockFixtures.otherCampus]
        await model.loadSchools()
        #expect(model.selectedSchool == nil)
        await model.continueWithSchool()
        #expect(auth.state == .signedOut(expired: false))
    }

    @Test func searchMatchesNameShortNameAndDomainIgnoringAccents() async {
        let (model, auth) = model()
        auth.universities = [MockFixtures.tec, MockFixtures.otherCampus]
        await model.loadSchools()
        model.schoolSearch = "monterréy"
        #expect(model.filteredSchools == [MockFixtures.tec])
        model.schoolSearch = "uanl"
        #expect(model.filteredSchools == [MockFixtures.otherCampus])
        model.schoolSearch = "tec.mx"
        #expect(model.filteredSchools == [MockFixtures.tec])
        model.schoolSearch = "  "
        #expect(model.filteredSchools.count == 2)
    }

    @Test func closingTheWebSheetStaysOnFindYourSchool() async {
        let (model, auth) = model()
        model.path = [.findSchool]
        model.selectedSchool = MockFixtures.tec
        auth.cancelsNextSignIn = true
        await model.continueWithSchool()
        #expect(model.path == [.findSchool])
        #expect(model.signInError == nil)
    }

    @Test func schoolListFailureOffersARetry() async {
        let (model, auth) = model()
        auth.nextError = .offline
        await model.loadSchools()
        #expect(model.schoolsFailedToLoad)
        await model.loadSchools()
        #expect(!model.schoolsFailedToLoad)
        #expect(model.schools == [MockFixtures.tec])
    }

    @Test func comingBackPicksUpWhereTheSessionIs() {
        #expect(model(.signedOut(expired: false)).0.path.isEmpty)
        #expect(model(.signedOut(expired: true)).0.path == [.signIn])
        #expect(model(.pendingApproval).0.path == [.pending])
        #expect(model(.needsProfile).0.path == [.about])
        #expect(model(.needsProfile).0.firstName == "Emilio")
        #expect(model(.needsGuidelines).0.path == [.guidelines])
    }

    @Test func reviewAccountSignsInWithAPassword() async {
        let (model, auth) = model()
        model.email = " \(MockFixtures.reviewEmail.uppercased()) "
        model.password = MockFixtures.reviewPassword
        await model.submitSignIn()
        #expect(auth.state == .signedIn(userID: auth.me.id))

        let (wrong, _) = self.model()
        wrong.email = MockFixtures.reviewEmail
        wrong.password = "nope"
        await wrong.submitSignIn()
        #expect(wrong.signInError == "That email and password don't match.")
    }

    /// N36: Create account → We're checking your account → (approved) → You're in → profile.
    @Test func newStudentSignsUpWaitsAndGetsIn() async {
        let (model, auth) = model()
        model.getStarted()
        model.createAccount()
        #expect(!model.isSignInSheetPresented)
        #expect(model.path == [.signUp])

        model.email = " A0123@Tec.mx "
        model.password = "short"
        await model.submitSignUp()
        #expect(model.passwordError == "Pick a stronger password: at least 8 characters.")
        #expect(auth.state == .signedOut(expired: false))

        model.password = "long-enough"
        await model.submitSignUp()
        #expect(model.passwordError == nil)
        #expect(auth.state == .pendingApproval)
        #expect(model.path == [.pending])
        #expect(model.password.isEmpty)

        await model.checkApproval()
        #expect(model.isStillPending)
        #expect(model.path == [.pending])

        auth.approveSignUp()
        await model.checkApproval()
        #expect(auth.state == .needsProfile)
        #expect(model.path == [.verified])
    }

    @Test func signUpNamesTheCampusWhenTheAddressIsNotAllowed() async {
        let (model, auth) = model()
        model.email = "someone@gmail.com"
        model.password = "long-enough"
        await model.submitSignUp()
        #expect(model.signUpError == "masUNO is just for Tec students right now. Use your Tec school account.")
        #expect(auth.state == .signedOut(expired: false))
    }

    @Test func waitingStudentCanSignOutAndComeBack() async {
        let (model, auth) = model()
        model.email = "a0123@tec.mx"
        model.password = "long-enough"
        await model.submitSignUp()
        await model.signOutWhilePending()
        #expect(auth.state == .signedOut(expired: false))
        #expect(model.path.isEmpty)

        model.haveAnAccount()
        model.password = "long-enough"
        await model.submitSignIn()
        #expect(model.path == [.pending])
    }

    @Test func nameFromSignInNeverReplacesWhatYouTyped() async {
        let (model, _) = model()
        model.firstName = "Mili"
        model.selectedSchool = MockFixtures.tec
        await model.continueWithSchool()
        #expect(model.firstName == "Mili")
        #expect(model.lastName == "")
    }
}

/// The wire formats in `docs/API.md`, with no server involved.
@MainActor
struct LiveContractTests {
    private func decode<Row: Decodable>(_ json: String) throws -> Row {
        try JSONDecoder().decode(Row.self, from: Data(json.utf8))
    }

    private let lookup = """
    {"id":"00000000-0000-0000-0000-00000000B001","name":"Tec de Monterrey","short_name":"Tec",
     "email_domain":"tec.mx","sso_provider":"azure","tenant_id":"abc","signup_enabled":true,
     "center_lat":25.6514,"center_lng":-100.2895}
    """

    @Test func universityLookupRowBecomesACampus() throws {
        let row: UniversityRow = try decode(lookup)
        let school = try #require(row.university)
        #expect(school.id == MockFixtures.tec.id)
        #expect(school.shortName == "Tec")
        #expect(school.emailDomain == "tec.mx")
        #expect(school.ssoProvider == .azure)
        #expect(school.signupEnabled)
        #expect(school.centerLongitude == -100.2895)
    }

    /// A provider added after this build shipped: nobody could sign in there, so it isn't listed.
    @Test func unknownProviderIsLeftOut() throws {
        let row: UniversityRow = try decode(lookup.replacingOccurrences(of: "\"azure\"", with: "\"okta\""))
        #expect(row.university == nil)
    }

    @Test func eachProviderHasItsOwnHint() {
        #expect(SSOProvider.azure.hintParameter == "domain_hint")
        #expect(SSOProvider.google.hintParameter == "hd")
    }

    @Test func appConfigRowsOverTheFallback() throws {
        let rows: [AppConfigRow] = try decode("""
        [{"key":"min_supported_version","value":"0.6"},{"key":"support_email","value":"help@masuno.app"},
         {"key":"privacy_url","value":"https://example.com/privacy"},{"key":"chat_enabled","value":true}]
        """)
        let config = AppConfig(rows: rows)
        #expect(config.minSupportedVersion == "0.6")
        #expect(config.supportEmail == "help@masuno.app")
        #expect(config.privacyURL.absoluteString == "https://example.com/privacy")
        #expect(AppConfig(rows: []) == .fallback)
    }

    @Test func activityRowDecodes() throws {
        let row: ActivityRow = try decode("""
        {"slug":"padel","kind":"sport","label_en":"Padel","label_es":"Pádel","emoji":"🏓","sort_order":5,
         "postable":true,"interest_selectable":false,"active":true}
        """)
        #expect(row.activity.slug == "padel")
        #expect(row.activity.labelES == "Pádel")
        #expect(!row.activity.interestSelectable)
    }

    @Test func myProfileDecidesTheNextStep() throws {
        let id = UUID()
        #expect(AuthState(profile: nil, userID: id) == .needsProfile)
        #expect(AuthState(profile: nil, isPending: true, userID: id) == .pendingApproval)
        let new: ProfileStatusRow = try decode(#"{"guidelines_accepted_at":null,"banned_at":null}"#)
        #expect(AuthState(profile: new, userID: id) == .needsGuidelines)
        let done: ProfileStatusRow = try decode(#"{"guidelines_accepted_at":"2026-11-07T00:00:00Z","banned_at":null}"#)
        #expect(AuthState(profile: done, userID: id) == .signedIn(userID: id))
        let banned: ProfileStatusRow = try decode(#"{"guidelines_accepted_at":null,"banned_at":"2026-11-07T00:00:00Z"}"#)
        #expect(AuthState(profile: banned, userID: id) == .suspended)
    }

    @Test func completeProfileSendsTheContractsParameters() throws {
        let input = ProfileInput(firstName: "Ana", lastName: "Solis", gradYear: 2028, interests: [MockFixtures.activity("soccer")])
        let data = try JSONEncoder().encode(CompleteProfileParams(input))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["p_first_name", "p_last_name", "p_grad_year", "p_interests", "p_locale"])
        #expect(json["p_interests"] as? [String] == ["soccer"])
    }

    @Test func signInFailuresMapToTheContractsErrors() {
        #expect(SignInFailure(error: "server_error", code: "unexpected_failure", message: "email_not_allowed").domainError == .emailNotAllowed)
        #expect(SignInFailure(error: "access_denied", message: "the user canceled").domainError == .schoolApprovalNeeded)
        #expect(SignInFailure(error: "server_error", message: "AADSTS90094: Admin consent is required").domainError == .schoolApprovalNeeded)
        #expect(SignInFailure(error: "consent_required").domainError == .schoolApprovalNeeded)
        #expect(SignInFailure(error: "server_error", message: "Something else").domainError == .signInFailed)
        #expect(SignInFailure().domainError == .signInFailed)
    }

    @Test func suggestedNamePrefersSeparateNames() {
        #expect(SuggestedName(metadata: ["given_name": "Ana", "family_name": "Solis", "name": "X Y"]) == SuggestedName(first: "Ana", last: "Solis"))
        #expect(SuggestedName(metadata: ["full_name": "Ana María Solis"]) == SuggestedName(first: "Ana", last: "María Solis"))
        #expect(SuggestedName(metadata: ["name": "Ana"]) == SuggestedName(first: "Ana", last: ""))
        #expect(SuggestedName(metadata: [:]) == nil)
    }

    @Test func placeholderKeysNeverReachTheNetwork() {
        #expect(SupabaseConfig(url: "https://YOUR-DEV-PROJECT-REF.supabase.co", anonKey: "YOUR-DEV-ANON-KEY") == nil)
        #expect(SupabaseConfig(url: "$(SUPABASE_URL)", anonKey: "key") == nil)
        #expect(SupabaseConfig(url: nil, anonKey: nil) == nil)
        #expect(SupabaseConfig(url: "http://abc.supabase.co", anonKey: "key") == nil)
        #expect(SupabaseConfig(url: "https://abc.supabase.co", anonKey: "")  == nil)
        #expect(SupabaseConfig(url: "https://abc.supabase.co", anonKey: "key")?.url.host() == "abc.supabase.co")
    }
}

/// The B7 rows and parameters: games, profiles and safety, as PostgREST sends and takes them.
@MainActor
struct LiveGameContractTests {
    private func decode<Row: Decodable>(_ json: String) throws -> Row {
        try JSONDecoder().decode(Row.self, from: Data(json.utf8))
    }

    private func encoded(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any])
    }

    private let catalog = ActivityCatalog { Activity.builtIn }

    /// A `game_cards` row the way Postgres formats it: microseconds and `+00:00`.
    private let card = """
    {"id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60","host_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc",
     "host_first_name":"Sofía","host_last_initial":"M","host_grad_year":2027,"activity_slug":"padel",
     "title":"Padel doubles","starts_at":"2026-11-10T23:30:00.123456+00:00","duration_minutes":90,
     "ends_at":"2026-11-11T01:00:00.123456+00:00","capacity":4,"going_count":4,"spots_left":0,"notes":null,
     "place_name":"Canchas de pádel","place_address":"Av. Eugenio Garza Sada 2501","lat":25.6505,"lng":-100.2899,
     "meet_point":"North gate","material_change_at":null,"cancelled_at":null,"auto_repost":true,
     "reposted_at":"2026-11-10T20:00:00+00:00","created_at":"2026-11-09T06:15:00.5+00:00",
     "sort_at":"2026-11-10T20:00:00+00:00","my_role":"player","my_joined_at":"2026-11-09T07:00:00+00:00",
     "has_blocked_attendee":false}
    """

    @Test func postgresTimestampsParse() throws {
        let date = try #require(ServerTime.date(from: "2026-11-10T23:30:00.123456+00:00"))
        #expect(ServerTime.string(from: date) == "2026-11-10T23:30:00.123Z")
        #expect(ServerTime.date(from: "2026-11-10T17:30:00-06:00") == ServerTime.date(from: "2026-11-10T23:30:00Z"))
        #expect(ServerTime.date(from: "yesterday") == nil)
    }

    @Test func gameCardRowBecomesAGame() throws {
        let row: GameCardRow = try decode(card)
        let game = row.game(activity: catalog.activity(slug:))
        #expect(game.host.displayName == "Sofía M.")
        #expect(game.activity.slug == "padel")
        #expect(game.activity.emoji == "🏓")
        #expect(game.durationMinutes == 90)
        #expect(game.endsAt.timeIntervalSince(game.startsAt) == 90 * 60)
        #expect(game.isFull)
        #expect(game.myRole == .player)
        #expect(game.status(now: game.startsAt.addingTimeInterval(-60)) == .going)
        #expect(game.place.latitude == 25.6505)
        #expect(game.meetPoint == "North gate")
        #expect(game.notes == nil)
        #expect(game.repostedAt == ServerTime.date(from: "2026-11-10T20:00:00Z"))
    }

    @Test func gameYouAreNotInHasNoRole() throws {
        let row: GameCardRow = try decode(card.replacingOccurrences(of: #""my_role":"player""#, with: #""my_role":null"#))
        #expect(row.game(activity: catalog.activity(slug:)).myRole == nil)
    }

    /// A `guest_games` row: no names, notes, meet-up spot or per-viewer columns to read.
    @Test func guestGameRowBecomesANamelessGame() throws {
        let row: GuestGameRow = try decode("""
        {"id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60","activity_slug":"padel","title":"Padel doubles",
         "starts_at":"2026-11-10T23:30:00.123456+00:00","duration_minutes":90,"ends_at":"2026-11-11T01:00:00.123456+00:00",
         "capacity":4,"going_count":3,"spots_left":1,"place_name":"Canchas de pádel",
         "place_address":"Av. Eugenio Garza Sada 2501","lat":25.6505,"lng":-100.2899,"reposted_at":null,
         "created_at":"2026-11-09T06:15:00.5+00:00","sort_at":"2026-11-09T06:15:00.5+00:00"}
        """)
        let game = row.game(activity: catalog.activity(slug:))
        #expect(game.hidesPeople)
        #expect(game.host == .hidden)
        #expect(game.activity.slug == "padel")
        #expect(game.endsAt.timeIntervalSince(game.startsAt) == 90 * 60)
        #expect(game.spotsLeft == 1)
        #expect(game.place.longitude == -100.2899)
        #expect(game.notes == nil && game.meetPoint == nil && game.myRole == nil)
        #expect(game.repostedAt == nil)
        #expect(game.createdAt == ServerTime.date(from: "2026-11-09T06:15:00.5Z"))
        #expect(game.status(now: game.startsAt.addingTimeInterval(-60)) == .open)
    }

    @Test func guestGamesParamsNameTheCampus() throws {
        let params = try encoded(GuestGamesParams(campus: MockFixtures.tec.id))
        #expect(Set(params.keys) == ["p_university"])
        #expect(params["p_university"] as? String == MockFixtures.tec.id.uuidString)
    }

    @Test func badTimestampFailsToDecode() {
        #expect(throws: DecodingError.self) {
            let _: GameCardRow = try decode(card.replacingOccurrences(of: "2026-11-10T23:30:00.123456+00:00", with: "soon"))
        }
    }

    /// A sport added on the server after this build still shows, but can't be posted or picked.
    @Test func unknownSportStillShows() throws {
        let row: GameCardRow = try decode(card.replacingOccurrences(of: #""padel""#, with: #""ultimate_frisbee""#))
        let activity = row.game(activity: catalog.activity(slug:)).activity
        #expect(activity.labelEN == "Ultimate Frisbee")
        #expect(!activity.postable)
        #expect(!activity.interestSelectable)
    }

    @Test func catalogKeepsTheBuiltInListWhenTheServerFails() async {
        let failing = ActivityCatalog { throw DomainError.offline }
        await failing.loadIfNeeded()
        #expect(failing.activities == Activity.builtIn)

        var served = Activity.builtIn
        served[0].labelEN = "Hoops"
        let live = ActivityCatalog { served }
        await live.loadIfNeeded()
        #expect(live.activity(slug: "basketball").labelEN == "Hoops")
    }

    @Test func attendeeAndActivityRowsDecode() throws {
        let attendee: AttendeeRow = try decode("""
        {"event_id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60","user_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc",
         "first_name":"Sofía","last_initial":"M","grad_year":2027,"role":"host","joined_at":"2026-11-09T06:15:00.5+00:00"}
        """)
        #expect(attendee.attendee.role == .host)
        #expect(attendee.attendee.person.displayName == "Sofía M.")

        let hidden: GameActivityRow = try decode("""
        {"id":"7a1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f61","event_id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60",
         "kind":"meet_point_updated","actor_id":null,"actor_first_name":null,"actor_last_initial":null,
         "actor_grad_year":null,"at":"2026-11-10T21:00:00.000001+00:00"}
        """)
        let entry = try #require(hidden.entry)
        #expect(entry.kind == .meetPointUpdated)
        #expect(entry.actor == nil)

        let future: GameActivityRow = try decode("""
        {"id":"7a1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f62","event_id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60",
         "kind":"message","at":"2026-11-10T21:00:00+00:00"}
        """)
        #expect(future.entry == nil)
    }

    @Test func myProfileRowBecomesAProfileOnItsCampus() throws {
        let row: MyProfileRow = try decode("""
        {"id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","first_name":"Ana","last_name":"Solis","grad_year":2028,
         "university_id":"00000000-0000-0000-0000-00000000B003","university_name":"masUNO Demo",
         "university_short_name":"Demo","university_email_domain":"demo.masuno.invalid","center_lat":25.66,
         "center_lng":-100.3,"interests":["soccer","padel"],"guidelines_accepted_at":null,"banned_at":null}
        """)
        let profile = row.profile(activity: catalog.activity(slug:))
        #expect(profile.university.id == MockFixtures.demoCampus.id)
        #expect(profile.university.shortName == "Demo")
        #expect(profile.interests.map(\.slug) == ["soccer", "padel"])
        #expect(profile.summary.displayName == "Ana S.")
    }

    @Test func blockedPersonRowDecodes() throws {
        let rows: [BlockedPersonRow] = try decode("""
        [{"user_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","first_name":"Alex","last_initial":"R","grad_year":2026}]
        """)
        #expect(rows.map(\.person.displayName) == ["Alex R."])
    }

    /// PostgREST matches a function by its argument names, so empty values go as null, never left out.
    @Test func gameParamsSendEveryArgument() throws {
        var draft = GameDraft(
            activity: MockFixtures.activity("soccer"), title: "  Pickup soccer ", startsAt: Date(timeIntervalSince1970: 1_794_355_200),
            durationMinutes: 60, capacity: 10, notes: "   ", place: MockFixtures.Places.basketballCourts, meetPoint: nil
        )
        let create = try encoded(GameDraftParams(draft))
        #expect(Set(create.keys) == [
            "p_activity_slug", "p_title", "p_starts_at", "p_duration_minutes", "p_capacity", "p_notes",
            "p_place_name", "p_place_address", "p_lat", "p_lng", "p_meet_point", "p_auto_repost",
        ])
        #expect(create["p_title"] as? String == "Pickup soccer")
        #expect(create["p_notes"] is NSNull)
        #expect(create["p_meet_point"] is NSNull)
        #expect(create["p_starts_at"] as? String == "2026-11-11T00:00:00.000Z")

        draft.meetPoint = " South gate "
        let id = UUID()
        let update = try encoded(GameDraftParams(id: id, draft))
        #expect(update["p_id"] as? String == id.uuidString)
        #expect(update["p_meet_point"] as? String == "South gate")
    }

    @Test func reportParamsSendExactlyOneTarget() throws {
        let id = UUID()
        let person = try encoded(ReportParams(target: .person(id), reason: .harassment, note: ""))
        #expect(person["p_user_id"] as? String == id.uuidString)
        #expect(person["p_game_id"] is NSNull)
        #expect(person["p_reason"] as? String == "harassment")
        #expect(person["p_note"] is NSNull)

        let game = try encoded(ReportParams(target: .game(id), reason: .spam, note: "Fake game"))
        #expect(game["p_user_id"] is NSNull)
        #expect(game["p_game_id"] as? String == id.uuidString)
        #expect(game["p_note"] as? String == "Fake game")
    }
}
