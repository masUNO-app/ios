import Foundation
import Testing
import UserNotifications
@testable import masUNO

@MainActor
private final class MemorySignOutMarker: SignOutMarker {
    var stored: String?
    func read() -> String? { stored }
    func write(_ id: String?) { stored = id }
}

/// An account whose signed-in id the test can change.
@MainActor
private final class StickyAuth: AuthService {
    var state: AuthState
    private(set) var signedOut = false
    var suggestedName: SuggestedName? { nil }

    init(_ state: AuthState) { self.state = state }

    func restoreSession() async {}
    func signIn(at school: University) async throws {}
    func signUp(email: String, password: String) async throws {}
    func signIn(email: String, password: String) async throws {}
    func refreshStatus() async throws {}
    func completeProfile(_ input: ProfileInput) async throws {}
    func acceptGuidelines() async throws {}
    func signOut() async throws {
        signedOut = true
        state = .signedOut(expired: false)
    }
    func deleteAccount() async throws {}
}

/// Records what `PushNotificationService` sends to the backend.
@MainActor
private final class SpyNotificationRepository: NotificationRepository {
    var registered: [(token: String, environment: String, locale: String, appVersion: String)] = []
    var unregistered: [String] = []
    var opened: [Int64] = []
    var prefs = NotificationPrefs.standard
    var winback: [Bool] = []
    var failUnregister = false
    var failMarkOpened = false
    var beforeUnregister: (() async -> Void)?
    var currentUserID = UUID()
    var serverTokens: [String: UUID] = [:]

    func registerDevice(token: String, environment: String, locale: String, appVersion: String) async throws {
        registered.append((token, environment, locale, appVersion))
        serverTokens[token] = currentUserID
    }

    func unregisterDevice(token: String) async throws {
        let requestUser = currentUserID
        await beforeUnregister?()
        unregistered.append(token)
        if failUnregister { throw DomainError.offline }
        if serverTokens[token] == requestUser { serverTokens[token] = nil }
    }

    func fetchPrefs() async throws -> NotificationPrefs { prefs }
    func setPrefs(_ prefs: NotificationPrefs) async throws { self.prefs = prefs }
    func setWinback(_ on: Bool) async throws { winback.append(on) }
    func setChatMuted(gameID: UUID, muted: Bool) async throws {}

    func markOpened(_ outboxID: Int64) async throws {
        opened.append(outboxID)
        if failMarkOpened { throw DomainError.offline }
    }
}

/// `AppGroupStore` is shared by every test, so this suite runs one test at a time.
@MainActor
@Suite(.serialized)
struct PushNotificationServiceTests {
    private let spy = SpyNotificationRepository()
    private let backend = MockBackend()
    private let defaults = UserDefaults(suiteName: "PushTests.\(UUID().uuidString)")!
    private let service: PushNotificationService

    init() {
        AppGroupStore.clearAccount()
        service = PushNotificationService(repository: spy, games: backend, chat: backend, defaults: defaults)
    }

    // MARK: Device token

    @Test func aNewTokenIsUploadedForThisBuild() async {
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        #expect(spy.registered.count == 1)
        #expect(spy.registered.first?.token == "ab12cd34ef56ab12cd34ef56")
        #expect(spy.registered.first?.environment == "sandbox")
        #expect(spy.registered.first?.appVersion == AppConfig.currentVersion)
        #expect(spy.registered.first?.locale.isEmpty == false)
    }

    @Test func launchUploadsAgainButAForegroundWithinTheHourDoesNot() async {
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        await service.refreshRegistration(force: false)
        #expect(spy.registered.count == 1)
        await service.refreshRegistration(force: true)
        #expect(spy.registered.count == 2)
    }

    @Test func theTokenSurvivesARelaunch() async {
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let relaunched = PushNotificationService(repository: spy, games: backend, chat: backend, defaults: defaults)
        await relaunched.refreshRegistration(force: true)
        #expect(spy.registered.last?.token == "ab12cd34ef56ab12cd34ef56")
    }

    @Test func withoutATokenNothingIsUploaded() async {
        await service.refreshRegistration(force: true)
        #expect(spy.registered.isEmpty)
    }

    @Test func signOutDropsTheTokenAndTheAccount() async {
        service.noteAccount(UUID())
        AppGroupStore.openChatID = UUID().uuidString
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        await service.unregister()
        #expect(spy.unregistered == ["ab12cd34ef56ab12cd34ef56"])
        #expect(AppGroupStore.myID == nil)
        #expect(AppGroupStore.openChatID == nil)

        await service.refreshRegistration(force: true)
        #expect(spy.registered.count == 1, "No upload after sign-out until iOS hands over a token again")
    }

    @Test func aFailedSignOutKeepsTheTokenToTryAgain() async {
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        spy.failUnregister = true
        await service.unregister()
        spy.failUnregister = false
        await service.unregister()
        #expect(spy.unregistered.count == 2, "A failed unregister keeps the token, or the old account keeps this phone")
    }

    @Test func aFailedSignOutRetriesOnTheNextLaunch() async {
        spy.failUnregister = true
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: defaults, notifications: spy
        )
        let marker = MemorySignOutMarker()
        let model = AppViewModel(auth: backend, catalog: backend, push: service, defaults: defaults, signOutMarker: marker)
        await model.signOut(store: store)

        #expect(model.session == .onboarding)
        #expect(model.signOutPendingUserID != nil)
        if case .signedIn = backend.state {} else {
            Issue.record("The session stays until the token can be removed")
        }
        #expect(spy.unregistered.count == 1)

        spy.failUnregister = false
        let relaunchedPush = PushNotificationService(
            repository: spy, games: backend, chat: backend, defaults: defaults
        )
        let relaunch = AppViewModel(
            auth: backend, catalog: backend, push: relaunchedPush, defaults: defaults, signOutMarker: marker
        )
        #expect(relaunch.session == .onboarding)
        #expect(relaunch.signOutPendingUserID == model.signOutPendingUserID)
        await relaunch.start()
        #expect(relaunch.signOutPendingUserID == nil)
        if case .signedOut = backend.state {} else {
            Issue.record("The next launch finishes sign-out")
        }
        #expect(spy.unregistered.count == 2)
    }

    @Test func aNewSignInIsNotSignedOutByThePendingRetry() async {
        let first = UUID()
        let second = UUID()
        let auth = StickyAuth(.signedIn(userID: first))
        spy.failUnregister = true
        await service.didRegister(token: "cd34ef56ab12cd34ef56ab12cd34ef56")
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let model = AppViewModel(
            auth: auth, catalog: backend, push: service, defaults: defaults, signOutMarker: MemorySignOutMarker()
        )
        await model.signOut(store: store)
        #expect(model.session == .onboarding)
        #expect(!auth.signedOut)

        auth.state = .signedIn(userID: second)
        await model.finishPendingSignOutIfNeeded()
        #expect(model.signOutPendingUserID == nil)
        #expect(!auth.signedOut)
        #expect(model.session == .signedIn)
    }

    @Test func signingBackInAsTheSameAccountStaysSignedIn() async {
        spy.failUnregister = true
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let marker = MemorySignOutMarker()
        let model = AppViewModel(auth: backend, catalog: backend, push: service, defaults: defaults, signOutMarker: marker)
        await model.signOut(store: store)
        #expect(model.session == .onboarding)

        let onboarding = OnboardingViewModel(auth: backend, catalog: backend)
        onboarding.onSignedIn = { model.noteSignInFinished() }
        onboarding.email = MockFixtures.reviewEmail
        onboarding.password = MockFixtures.reviewPassword
        await onboarding.submitSignIn()

        #expect(model.signOutPendingUserID == nil)
        #expect(model.session == .signedIn)
        await model.finishPendingSignOutIfNeeded()
        if case .signedIn = backend.state {} else {
            Issue.record("Signing back in as the same account stays signed in")
        }
        #expect(model.session == .signedIn)
        await service.refreshRegistration(force: true)
        #expect(spy.registered.count == 2)
    }

    @Test func signingInDuringTheRetryIsNotSignedOut() async {
        spy.failUnregister = true
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let model = AppViewModel(
            auth: backend, catalog: backend, push: service, defaults: defaults, signOutMarker: MemorySignOutMarker()
        )
        await model.signOut(store: store)
        spy.failUnregister = false
        spy.beforeUnregister = { model.noteSignInFinished() }
        await model.finishPendingSignOutIfNeeded()
        if case .signedIn = backend.state {} else {
            Issue.record("A sign-in that finishes during the retry stays signed in")
        }
        #expect(model.session == .signedIn)
    }

    @Test(arguments: [false, true])
    func signingInDuringTheRetryKeepsTheDeviceRegistration(switchAccount: Bool) async {
        let originalID = UUID()
        let activeID = switchAccount ? UUID() : originalID
        let auth = StickyAuth(.signedIn(userID: originalID))
        let token = "ab12cd34ef56ab12cd34ef56"
        spy.currentUserID = originalID
        await service.didRegister(token: token)
        spy.failUnregister = true
        let store = GameStore(games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults)
        let model = AppViewModel(auth: auth, catalog: backend, push: service, defaults: defaults, signOutMarker: MemorySignOutMarker())
        await model.signOut(store: store)
        let gate = NotificationTestGate()
        spy.failUnregister = false
        spy.beforeUnregister = { await gate.wait() }
        let retry = Task { await model.finishPendingSignOutIfNeeded() }
        await gate.waitUntilEntered()
        auth.state = .signedIn(userID: activeID)
        spy.currentUserID = activeID
        model.noteSignInFinished()
        var registrationStarted = false
        let registration = Task {
            registrationStarted = true
            await service.didRegister(token: token)
        }
        while !registrationStarted { await Task.yield() }
        gate.open()
        await retry.value
        await registration.value
        #expect(auth.state == .signedIn(userID: activeID))
        #expect(model.session == .signedIn)
        #expect(AppGroupStore.myID == activeID.uuidString)
        #expect(defaults.string(forKey: "apnsDeviceToken") == token)
        #expect(spy.serverTokens[token] == activeID)
    }

    @Test func aPendingSignOutWaitsUntilTheSessionIsKnown() async {
        let id = UUID()
        let auth = StickyAuth(.signedIn(userID: id))
        spy.failUnregister = true
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let model = AppViewModel(
            auth: auth, catalog: backend, push: service, defaults: defaults, signOutMarker: MemorySignOutMarker()
        )
        await model.signOut(store: store)
        auth.state = .loading
        await model.finishPendingSignOutIfNeeded()
        #expect(model.signOutPendingUserID == id)
        #expect(!auth.signedOut)
    }

    @Test func aReinstallKeepsThePendingSignOut() async {
        spy.failUnregister = true
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        let marker = MemorySignOutMarker()
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let model = AppViewModel(auth: backend, catalog: backend, push: service, defaults: defaults, signOutMarker: marker)
        await model.signOut(store: store)
        let fresh = UserDefaults(suiteName: "Reinstall.\(UUID().uuidString)")!
        let relaunch = AppViewModel(auth: backend, catalog: backend, push: service, defaults: fresh, signOutMarker: marker)
        #expect(relaunch.signOutPendingUserID == model.signOutPendingUserID)
        #expect(relaunch.session == .onboarding)
    }

    @Test func deletingTheAccountClearsThePhoneEvenIfUnregisterFails() async {
        service.noteAccount(UUID())
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        spy.failUnregister = true
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend, defaults: defaults
        )
        let model = AppViewModel(auth: backend, catalog: backend, push: service, defaults: defaults)
        await model.deleteAccount(store: store)
        #expect(AppGroupStore.myID == nil)
        let again = PushNotificationService(repository: spy, games: backend, chat: backend, defaults: defaults)
        await again.refreshRegistration(force: true)
        #expect(spy.registered.count == 1)
    }

    @Test func theOpenScreenIsForgottenWhenTheAppIsKilled() {
        let stored = UserDefaults(suiteName: AppGroupStore.suiteName)
        stored?.removeObject(forKey: "openChatID")
        stored?.removeObject(forKey: "openGameID")
        let chat = UUID().uuidString
        let game = UUID().uuidString
        AppGroupStore.openChatID = chat
        AppGroupStore.openGameID = game
        #expect(AppGroupStore.openChatID == chat)
        #expect(stored?.string(forKey: "openChatID") == nil)
        #expect(stored?.string(forKey: "openGameID") == nil)
        AppGroupStore.clearAccount()
        #expect(AppGroupStore.openChatID == nil)
        #expect(AppGroupStore.openGameID == nil)
    }

    @Test func theSameTokenTwiceInAMinuteUploadsOnce() async {
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        await service.didRegister(token: "ab12cd34ef56ab12cd34ef56")
        #expect(spy.registered.count == 1, "didRegister follows the hourly check, or every launch uploads twice")
    }

    // MARK: Banners in the foreground

    @Test func bannersShowUnlessThatScreenIsOpen() {
        let gameID = UUID()
        let chat = NotificationPayload(kind: "chat_message", gameID: gameID)
        let reminder = NotificationPayload(kind: "reminder", gameID: gameID)
        let shown: UNNotificationPresentationOptions = [.banner, .sound, .list]

        #expect(service.presentationOptions(for: nil) == shown)
        #expect(service.presentationOptions(for: chat) == shown)
        #expect(service.presentationOptions(for: reminder) == shown)

        AppGroupStore.openGameID = gameID.uuidString
        #expect(service.presentationOptions(for: reminder) == [])
        #expect(service.presentationOptions(for: chat) == shown, "The game screen doesn't hide its chat")

        AppGroupStore.openChatID = gameID.uuidString
        #expect(service.presentationOptions(for: chat) == [])

        let otherGame = NotificationPayload(kind: "reminder", gameID: UUID())
        #expect(service.presentationOptions(for: otherGame) == shown)
    }

    @Test func aBannerRefreshesItsGameEvenWhenHidden() {
        let gameID = UUID()
        var refreshed: [UUID] = []
        service.onRefreshGame = { refreshed.append($0) }
        AppGroupStore.openGameID = gameID.uuidString
        _ = service.presentationOptions(for: NotificationPayload(kind: "game_changed", gameID: gameID))
        _ = service.presentationOptions(for: NotificationPayload(kind: "signup_approved"))
        #expect(refreshed == [gameID])
    }

    // MARK: Taps and actions

    @Test func aTapMarksItOpenedAndRoutes() async {
        let gameID = UUID()
        var opened: [URL?] = []
        service.onOpen = { opened.append($0) }
        let payload = NotificationPayload(kind: "spot_open", gameID: gameID, outboxID: 42)
        await service.handle(action: UNNotificationDefaultActionIdentifier, payload: payload, reply: nil)
        #expect(spy.opened == [42])
        #expect(opened == [URL(string: "masuno://game/\(gameID.uuidString)")])
    }

    @Test func aTapStillRoutesWhenMarkingOpenedFails() async {
        var opened: [URL?] = []
        service.onOpen = { opened.append($0) }
        spy.failMarkOpened = true
        await service.handle(action: UNNotificationDefaultActionIdentifier, payload: NotificationPayload(kind: "winback", outboxID: 7), reply: nil)
        #expect(opened == [URL(string: "masuno://map")])
    }

    @Test func aTapBeforeTheInterfaceIsReadyWaitsOnce() async {
        let gameID = UUID()
        await service.handle(action: UNNotificationDefaultActionIdentifier, payload: NotificationPayload(kind: "chat_message", gameID: gameID), reply: nil)
        #expect(service.pendingRoute == URL(string: "masuno://game/\(gameID.uuidString)/chat"))
        #expect(service.consumePendingRoute() == URL(string: "masuno://game/\(gameID.uuidString)/chat"))
        #expect(service.consumePendingRoute() == nil)
    }

    @Test func aTapOnSomethingThatIsntOursDoesNothing() async {
        var opened: [URL?] = []
        service.onOpen = { opened.append($0) }
        await service.handle(action: UNNotificationDefaultActionIdentifier, payload: nil, reply: nil)
        #expect(opened.isEmpty)
        #expect(spy.opened.isEmpty)
    }

    @Test func replyFromTheBannerPostsInTheChat() async throws {
        let gameID = MockFixtures.GameID.going
        try await backend.acceptChatRules()
        let before = try await backend.fetchMessages(gameID: gameID, before: nil, limit: 500).count
        await service.handle(action: "REPLY", payload: NotificationPayload(kind: "chat_message", gameID: gameID), reply: "On my way")
        await service.handle(action: "REPLY", payload: NotificationPayload(kind: "chat_message", gameID: gameID), reply: "   ")
        let messages = try await backend.fetchMessages(gameID: gameID, before: nil, limit: 500)
        #expect(messages.count == before + 1, "A blank reply is not sent")
        #expect(messages.last?.body == "On my way")
    }

    @Test func countMeInJoinsTheGame() async throws {
        let gameID = MockFixtures.GameID.open
        var opened: [URL?] = []
        service.onOpen = { opened.append($0) }
        await service.handle(action: "COUNT_ME_IN", payload: NotificationPayload(kind: "spot_open", gameID: gameID), reply: nil)
        let game = try #require(try await backend.fetchGames(ids: [gameID]).first)
        #expect(game.myRole == .player)
        #expect(opened.isEmpty, "The action joins without opening the app")
    }

    @Test func countMeInOnAFullGameDoesntJoin() async throws {
        let gameID = MockFixtures.GameID.full
        await service.handle(action: "COUNT_ME_IN", payload: NotificationPayload(kind: "spot_open", gameID: gameID), reply: nil)
        let game = try #require(try await backend.fetchGames(ids: [gameID]).first)
        #expect(game.myRole == nil)
    }

    // MARK: Primer

    @Test func thePrimerComesBackOnceAfterNotNow() {
        let me = UUID()
        #expect(service.authorizationStatus == .notDetermined)
        #expect(!service.shouldOfferPrimer(accountID: nil))
        #expect(service.shouldOfferPrimer(accountID: me))
        service.recordPrimerDecline(accountID: me)
        #expect(service.shouldOfferPrimer(accountID: me))
        service.recordPrimerDecline(accountID: me)
        #expect(!service.shouldOfferPrimer(accountID: me))
        #expect(service.shouldOfferPrimer(accountID: UUID()), "Each account gets its own count")
    }

    @Test func acceptingThePrimerStopsIt() {
        let me = UUID()
        service.recordPrimerAccepted(accountID: me)
        #expect(!service.shouldOfferPrimer(accountID: me))
    }

    // MARK: Preferences

    @Test func preferencesPassThrough() async throws {
        var prefs = try await service.fetchPrefs()
        #expect(prefs == .standard)
        prefs.chat = false
        try await service.setPrefs(prefs)
        try await service.setWinback(true)
        #expect(spy.prefs.chat == false)
        #expect(spy.winback == [true])
    }

    // MARK: Categories

    @Test func everySampleCategoryIsRegistered() async throws {
        service.registerCategories()
        let registered = await UNUserNotificationCenter.current().notificationCategories()
        let byID = Dictionary(uniqueKeysWithValues: registered.map { ($0.identifier, $0) })
        for sample in try NotificationSamples.all() {
            guard let category = sample.aps["category"] as? String else { continue }
            #expect(byID[category] != nil, "\(sample.name) uses \(category)")
        }
        #expect(byID["CHAT"]?.actions.map(\.identifier) == ["REPLY", "MARK_READ"])
        #expect(byID["REMINDER"]?.actions.map(\.identifier) == ["DIRECTIONS"])
        for id in ["SPOT_OPEN", "INTEREST", "SAVED_SOON"] {
            #expect(byID[id]?.actions.map(\.identifier) == ["COUNT_ME_IN"])
        }
    }
}

// MARK: - Payloads

/// The `.apns` files in `MasUnoNotifications/Samples`, read from the repo.
private enum NotificationSamples {
    struct Sample {
        let name: String
        let userInfo: [AnyHashable: Any]
        var aps: [String: Any] { userInfo["aps"] as? [String: Any] ?? [:] }
    }

    static func all() throws -> [Sample] {
        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "MasUnoNotifications/Samples")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "apns" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            return Sample(name: file.deletingPathExtension().lastPathComponent, userInfo: object as? [AnyHashable: Any] ?? [:])
        }
    }
}

struct NotificationPayloadTests {
    @Test func everySampleDecodesAndRoutes() throws {
        let samples = try NotificationSamples.all()
        #expect(samples.count == 11)
        for sample in samples {
            let payload = try #require(NotificationPayload(userInfo: sample.userInfo), "\(sample.name) didn't decode")
            #expect(payload.kind == sample.name, "The file name is the kind")
            switch payload.kind {
            case "signup_approved":
                #expect(payload.routeURL() == nil)
            case "winback":
                #expect(payload.routeURL() == URL(string: "masuno://map"))
            case "chat_message":
                #expect(payload.routeURL()?.absoluteString.hasSuffix("/chat") == true)
            default:
                let gameID = try #require(payload.gameID, "\(sample.name) has no game")
                #expect(payload.routeURL() == URL(string: "masuno://game/\(gameID.uuidString)"))
            }
        }
    }

    @Test func threadsMatchTheGame() throws {
        for sample in try NotificationSamples.all() {
            guard let payload = NotificationPayload(userInfo: sample.userInfo), let gameID = payload.gameID,
                  let thread = sample.aps["thread-id"] as? String
            else { continue }
            let prefix = payload.kind == "chat_message" ? "chat:" : "game:"
            #expect(thread == prefix + gameID.uuidString.lowercased(), "\(sample.name)")
        }
    }

    @Test func somethingThatIsntOursIsNil() {
        #expect(NotificationPayload(userInfo: [:]) == nil)
        #expect(NotificationPayload(userInfo: ["aps": ["alert": "Hi"]]) == nil)
        #expect(NotificationPayload(userInfo: ["kind": "reminder", "game_id": "not-a-uuid"]) == nil)
        #expect(NotificationPayload(userInfo: ["kind": 3]) == nil)
    }

    @Test func unknownKindsAndFieldsStillOpenTheGame() throws {
        let id = UUID()
        let payload = try #require(NotificationPayload(userInfo: ["kind": "something_new", "game_id": id.uuidString, "extra": true]))
        #expect(payload.routeURL() == URL(string: "masuno://game/\(id.uuidString)"))
        #expect(payload.others.isEmpty)
    }

    @Test func aGameKindWithoutAGameOpensNothing() throws {
        let payload = try #require(NotificationPayload(userInfo: ["kind": "reminder"]))
        #expect(payload.routeURL() == nil)
        let chat = try #require(NotificationPayload(userInfo: ["kind": "chat_message"]))
        #expect(chat.routeURL() == nil)
    }

    @Test func encodingRoundTrips() throws {
        let original = NotificationPayload(
            kind: "chat_message", gameID: UUID(), outboxID: 9,
            game: .init(title: "Hoops", sport: "basketball"),
            sender: .init(id: UUID(), name: "Maya C.", initials: "MC"),
            body: "Hi", count: 2, place: .init(name: "Courts", lat: 1, lng: 2)
        )
        let data = try JSONEncoder().encode(original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["game_id"] != nil)
        #expect(object["outbox_id"] as? Int == 9)
        #expect(object["others"] == nil, "An empty list isn't written")
        let decoded = try JSONDecoder().decode(NotificationPayload.self, from: data)
        #expect(decoded.gameID == original.gameID)
        #expect(decoded.sender?.name == "Maya C.")
        #expect(decoded.place?.lng == 2)
        #expect(decoded.count == 2)
    }

    @Test func prefsUseTheServerColumnNames() throws {
        let data = try JSONEncoder().encode(NotificationPrefs.standard)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(Set(object.keys) == ["interest_match", "spot_open", "reminders", "hosting", "chat", "winback"])
        #expect(object["winback"] == false, "Tips are off until the person opts in")
        #expect(object.filter { $0.key != "winback" }.values.allSatisfy { $0 })
    }
}

// MARK: - Spot alerts in the store

@MainActor
struct SpotAlertTests {
    let backend = MockBackend()
    let store: GameStore

    init() async {
        store = Self.makeStore(backend)
        await store.load()
    }

    private static func makeStore(_ backend: MockBackend, defaults: UserDefaults? = nil) -> GameStore {
        GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: defaults ?? UserDefaults(suiteName: "SpotAlertTests.\(UUID().uuidString)")!
        )
    }

    /// Waits for the store's fire-and-forget sync task.
    private func settle(_ duration: Duration = .milliseconds(50)) async {
        try? await Task.sleep(for: duration)
    }

    @Test func notifyMeSavesTheGameAndTellsTheServer() async {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        #expect(store.hasSpotAlert(id))
        #expect(store.isSaved(id))
        await settle()

        // A new phone, or a reinstall, starts with empty defaults and should learn it from the server (SPEC E17).
        let otherPhone = Self.makeStore(backend)
        await otherPhone.load()
        // Fails while saves only come back through the map, which leaves out full games.
        #expect(otherPhone.hasSpotAlert(id))
        #expect(otherPhone.isSaved(id))
    }

    @Test func aServerBookmarkOnAnOpenGameReachesANewPhone() async {
        let id = MockFixtures.GameID.open
        store.toggleSaved(id)
        await settle()
        let otherPhone = Self.makeStore(backend)
        await otherPhone.load()
        #expect(otherPhone.isSaved(id))
    }

    @Test func turningNotifyMeOffKeepsTheSave() async {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        await settle()
        store.toggleSpotAlert(id)
        #expect(!store.hasSpotAlert(id))
        await settle()
        #expect(!store.hasSpotAlert(id))
        #expect(store.isSaved(id))

        let otherPhone = Self.makeStore(backend)
        await otherPhone.load()
        #expect(!otherPhone.hasSpotAlert(id))
    }

    @Test func unsavingAlsoStopsNotifyMe() async {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        await settle()
        store.toggleSaved(id)
        await settle()
        #expect(!store.isSaved(id))
        #expect(!store.hasSpotAlert(id))
    }

    @Test func aBookmarkOlderThanTwoWeeksIsLeftOut() async throws {
        let id = MockFixtures.GameID.open
        store.toggleSaved(id)
        await settle()
        backend.setEndsAt(backend.now.addingTimeInterval(-15 * 24 * 3600), for: id)
        let fetched = try await backend.fetchBookmarkedGames()
        #expect(!fetched.contains { $0.id == id })
    }

    @Test func aFailedNotifyMeSaysSo() async {
        backend.nextError = .offline
        store.toggleSpotAlert(MockFixtures.GameID.full)
        await settle()
        #expect(store.notice == DomainError.offline.message)
    }

    @Test func aSlowOnReplyDoesntUndoALaterOff() async {
        let id = MockFixtures.GameID.full
        backend.latency = .milliseconds(300)
        store.toggleSpotAlert(id)
        await settle()          // the "on" call is now waiting on the slow reply
        backend.latency = .zero
        store.toggleSpotAlert(id)
        await settle(.milliseconds(500))
        await store.waitForBookmarkWrites()
        #expect(!store.hasSpotAlert(id), "A late reply for an older toggle is ignored")
        let server = try? await backend.fetchGame(id: id)
        #expect(server?.spotAlert == false)
    }

    @Test func aSlowAlertOnFollowedByUnsaveEndsUnsavedOnTheServer() async throws {
        let id = MockFixtures.GameID.full
        let gate = NotificationTestGate()
        backend.beforeBookmarkWrite = { await gate.wait() }
        store.toggleSpotAlert(id)
        await gate.waitUntilEntered()
        store.toggleSaved(id)
        gate.open()
        await store.waitForBookmarkWrites()
        let server = try await backend.fetchGame(id: id)
        #expect(!server.isBookmarked && !server.spotAlert)
        #expect(!store.isSaved(id) && !store.hasSpotAlert(id))
    }

    @Test func aSlowSaveFollowedByUnsaveEndsUnsavedOnTheServer() async throws {
        let id = MockFixtures.GameID.open
        let gate = NotificationTestGate()
        backend.beforeBookmarkWrite = { await gate.wait() }
        store.toggleSaved(id)
        await gate.waitUntilEntered()
        store.toggleSaved(id)
        gate.open()
        await store.waitForBookmarkWrites()
        let server = try await backend.fetchGame(id: id)
        #expect(!server.isBookmarked && !server.spotAlert)
        #expect(!store.isSaved(id) && !store.hasSpotAlert(id))
    }

    @Test func remoteUnsaveIsAppliedOnRefresh() async throws {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        await store.waitForBookmarkWrites()
        _ = try await backend.setBookmark(id: id, on: false)
        await store.refreshSaved()
        #expect(!store.isSaved(id) && !store.hasSpotAlert(id))
    }

    @Test func remoteAlertDisableKeepsTheSave() async throws {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        await store.waitForBookmarkWrites()
        _ = try await backend.setSpotAlert(id: id, on: false)
        await store.refreshSaved()
        #expect(store.isSaved(id) && !store.hasSpotAlert(id))
    }

    @Test func anOlderServerSnapshotDoesNotUndoANewerLocalSave() async {
        let id = MockFixtures.GameID.full
        store.toggleSaved(id)
        await store.waitForBookmarkWrites()
        let gate = NotificationTestGate()
        backend.beforeBookmarkedGamesReply = { await gate.wait() }
        let refresh = Task { await store.refreshSaved() }
        await gate.waitUntilEntered()
        store.toggleSpotAlert(id)
        await store.waitForBookmarkWrites()
        gate.open()
        await refresh.value
        #expect(store.isSaved(id) && store.hasSpotAlert(id))
    }

    @Test func anEditAlreadyPendingAtRefreshStartKeepsItsOptimisticState() async {
        let id = MockFixtures.GameID.full
        store.toggleSaved(id)
        await store.waitForBookmarkWrites()
        let gate = NotificationTestGate()
        backend.beforeBookmarkWrite = { await gate.wait() }
        store.toggleSpotAlert(id)
        await gate.waitUntilEntered()
        await store.refreshSaved()
        #expect(store.isSaved(id) && store.hasSpotAlert(id))
        gate.open()
        await store.waitForBookmarkWrites()
        #expect(store.isSaved(id) && store.hasSpotAlert(id))
    }

    @Test func aRelaunchDoesNotReimportAnAlreadySyncedRemoteSave() async throws {
        let id = MockFixtures.GameID.full
        let defaults = UserDefaults(suiteName: "RemoteRelaunch.\(UUID().uuidString)")!
        _ = try await backend.setBookmark(id: id, on: true)
        let first = Self.makeStore(backend, defaults: defaults)
        await first.load()
        #expect(first.isSaved(id))
        _ = try await backend.setBookmark(id: id, on: false)
        let relaunched = Self.makeStore(backend, defaults: defaults)
        await relaunched.load()
        #expect(!relaunched.isSaved(id))
        let server = try await backend.fetchGame(id: id)
        #expect(!server.isBookmarked)
    }

    @Test func aFailedRefreshKeepsCachedSavesAndAlerts() async {
        let id = MockFixtures.GameID.full
        store.toggleSpotAlert(id)
        await store.waitForBookmarkWrites()
        backend.nextError = .offline
        await store.refreshSaved()
        #expect(store.isSaved(id) && store.hasSpotAlert(id))
    }

    @Test func aBookmarkOlderThanTheQueryWindowIsNotMistakenForARemoteRemoval() async {
        let id = MockFixtures.GameID.open
        store.toggleSaved(id)
        await store.waitForBookmarkWrites()
        backend.setEndsAt(backend.now.addingTimeInterval(-15 * 24 * 3600), for: id)
        await store.refreshSaved()
        #expect(store.isSaved(id))
    }

    @Test func aFailedUnsaveDoesntStayHidden() async {
        let id = MockFixtures.GameID.lastSpot
        store.toggleSaved(id)
        await settle()
        backend.nextError = .offline
        store.toggleSaved(id)
        await settle()
        // The server still has the bookmark, so the phone should show it as saved.
        #expect(store.isSaved(id), "A failed unsave is rolled back")
    }
}
