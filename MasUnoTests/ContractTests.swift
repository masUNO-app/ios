import Foundation
import Testing
@testable import MasUno

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
        let auth = MockBackend(state: .signedOut(email: nil))
        #expect(try await auth.signInMethod(for: "a0123@tec.mx") == .otp)
        try await auth.sendCode(to: "a0123@tec.mx")
        try await auth.verifyCode("123456", email: "a0123@tec.mx")
        #expect(auth.state == .needsProfile)
        try await auth.completeProfile(input)
        #expect(auth.state == .needsGuidelines)
        try await auth.acceptGuidelines()
        #expect(auth.state == .signedIn(userID: auth.me.id))
        #expect(try await auth.fetchMyProfile()?.summary.displayName == "Emilio G.")
    }

    @Test func wrongAndExpiredCodes() async throws {
        let auth = MockBackend(state: .signedOut(email: nil))
        await #expect(throws: DomainError.codeInvalid) { try await auth.verifyCode("000000", email: "a@tec.mx") }
        await #expect(throws: DomainError.codeExpired) { try await auth.verifyCode("111111", email: "a@tec.mx") }
    }

    @Test func otherDomainsAreRefused() async throws {
        let auth = MockBackend(state: .signedOut(email: nil))
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.sendCode(to: "someone@gmail.com") }
    }

    /// Review accounts are Gmail aliases, so the method check comes before the domain check.
    @Test func reviewAccountUsesAPassword() async throws {
        let auth = MockBackend(state: .signedOut(email: nil))
        #expect(try await auth.signInMethod(for: MockFixtures.reviewEmail) == .password)
        await #expect(throws: DomainError.invalidCredentials) {
            try await auth.signIn(email: MockFixtures.reviewEmail, password: "nope")
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

    @Test func expiredSessionKeepsTheEmail() async throws {
        let auth = MockBackend()
        auth.expireSession(email: "a0123@tec.mx")
        #expect(auth.state == .signedOut(email: "a0123@tec.mx"))
        await #expect(throws: DomainError.notAuthenticated) { try await auth.joinGame(id: MockFixtures.GameID.open) }
    }

    @Test func deleteAccountCancelsHostedAndFreesJoined() async throws {
        let auth = MockBackend()
        try await auth.deleteAccount()
        #expect(auth.state == .signedOut(email: nil))
        #expect(auth.games.first { $0.id == MockFixtures.GameID.hosting }?.isCancelled == true)
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
        let auth = MockBackend(state: .signedOut(email: nil))
        #expect(try await auth.signInMethod(for: "a0123@tec.mx") == .otp)
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signInMethod(for: "a@uanl.edu.mx") }

        // Tec doesn't work out: the campus changes on the server, with no app change.
        auth.openUniversities = [MockFixtures.otherCampus]
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signInMethod(for: "a0123@tec.mx") }
        #expect(try await auth.signInMethod(for: "a@uanl.edu.mx") == .otp)

        try await auth.sendCode(to: "a@uanl.edu.mx")
        try await auth.verifyCode("123456", email: "a@uanl.edu.mx")
        try await auth.completeProfile(ProfileInput(
            firstName: "Ana", lastName: "Solis", gradYear: 2028, interests: [MockFixtures.activity("soccer")]
        ))
        #expect(try await auth.fetchMyProfile()?.university == MockFixtures.otherCampus)
    }

    @Test func domainMatchIsExact() async {
        let auth = MockBackend(state: .signedOut(email: nil))
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signInMethod(for: "a@mail.tec.mx") }
        await #expect(throws: DomainError.emailNotAllowed) { try await auth.signInMethod(for: "tec.mx") }
    }

    @Test func reviewAccountLandsOnTheDemoCampus() async throws {
        let auth = MockBackend(state: .signedOut(email: nil))
        try await auth.signIn(email: MockFixtures.reviewEmail, password: MockFixtures.reviewPassword)
        #expect(try await auth.fetchMyProfile()?.university == MockFixtures.demoCampus)
        #expect(try await auth.fetchOpenUniversities() == [MockFixtures.tec])
    }

    @Test func onboardingCopyFollowsTheCampus() async {
        let auth = MockBackend(state: .signedOut(email: nil))
        let other = OnboardingViewModel(auth: auth, campus: MockFixtures.otherCampus)
        #expect(other.emailPlaceholder == "you@uanl.edu.mx")
        other.email = "someone@gmail.com"
        await other.submitEmail()
        #expect(other.emailError == "masUNO is just for UANL students right now. Use your @uanl.edu.mx email.")

        let generic = OnboardingViewModel(auth: auth)
        generic.email = "someone@gmail.com"
        await generic.submitEmail()
        #expect(generic.emailError == "masUNO isn't open at your school yet.")
    }

    @Test func maskedEmailKeepsTheRealDomain() {
        let auth = MockBackend(state: .signedOut(email: nil))
        let model = OnboardingViewModel(auth: auth)
        model.email = "a01234567@uanl.edu.mx"
        #expect(model.maskedEmail == "a0…@uanl.edu.mx")
    }

    @Test func storeRemembersTheCampusForOfflineLaunches() async {
        let backend = MockBackend()
        let defaults = UserDefaults(suiteName: "CampusTests.\(UUID().uuidString)")!
        let first = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend, defaults: defaults)
        await first.load()
        #expect(first.campus == MockFixtures.tec)

        let offline = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend, defaults: defaults)
        #expect(offline.campus == MockFixtures.tec)

        offline.reset()
        let afterSignOut = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend, defaults: defaults)
        #expect(afterSignOut.campus == nil)
    }
}
