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

    @Test func deleteAccountCancelsHostedAndFreesJoined() async throws {
        let auth = MockBackend()
        try await auth.deleteAccount()
        #expect(auth.state == .signedOut(expired: false))
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

@MainActor
struct OnboardingFlowTests {
    private func model(_ state: AuthState = .signedOut(expired: false)) -> (OnboardingViewModel, MockBackend) {
        let auth = MockBackend(state: state)
        return (OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.tec), auth)
    }

    @Test func newStudentGoesThroughPrimerSheetSchoolAndVerified() async {
        let (model, auth) = model()
        #expect(model.path.isEmpty)
        model.path.append(.locationPrimer)
        model.continueFromPrimer()
        #expect(model.isSignInSheetPresented)
        model.findMySchool()
        #expect(!model.isSignInSheetPresented)
        #expect(model.path == [.locationPrimer, .findSchool])

        await model.loadSchools()
        #expect(model.selectedSchool == MockFixtures.tec)
        await model.continueWithSchool()
        #expect(auth.state == .needsProfile)
        #expect(model.path == [.locationPrimer, .findSchool, .verified])
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
        model.path = [.locationPrimer, .findSchool]
        model.selectedSchool = MockFixtures.tec
        auth.cancelsNextSignIn = true
        await model.continueWithSchool()
        #expect(model.path == [.locationPrimer, .findSchool])
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
        #expect(model(.signedOut(expired: true)).0.path == [.findSchool])
        #expect(model(.needsProfile).0.path == [.about])
        #expect(model(.needsProfile).0.firstName == "Emilio")
        #expect(model(.needsGuidelines).0.path == [.guidelines])
    }

    @Test func reviewAccountSignsInWithoutTheSchoolPage() async {
        let (model, auth) = model()
        model.email = " \(MockFixtures.reviewEmail.uppercased()) "
        model.password = MockFixtures.reviewPassword
        await model.submitReviewAccount()
        #expect(auth.state == .signedIn(userID: auth.me.id))

        let (wrong, _) = self.model()
        wrong.email = MockFixtures.reviewEmail
        wrong.password = "nope"
        await wrong.submitReviewAccount()
        #expect(wrong.reviewError == "That email and password don't match.")
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
