import Foundation
import Observation

/// Root presentation state (SPEC §7.3): the launch gate, the navigation path and
/// app-level sheets. Sheets that open on top of a screen or another sheet
/// (location picker, Who's going, report) are presented by that screen.
@Observable
final class AppViewModel {
    /// Where launch lands: version check → session → Map.
    enum Session: Equatable {
        case launching
        case updateRequired
        case onboarding
        case suspended
        case signedIn
    }

    enum Sheet: Identifiable, Hashable {
        case gameForm(editing: UUID?)
        /// "Play again": a new game that starts from an earlier one's sport, place and details.
        case playAgain(UUID)

        var id: Self { self }
    }

    var path: [Route] = []
    var sheet: Sheet?
    /// The game you just took a spot in from the map or Saved. Its details open with your spot
    /// still empty for a moment, so you see yourself land on the court.
    private(set) var arrivingIn: UUID?
    private(set) var config = AppConfig.fallback
    private(set) var isUpdateRequired = false
    /// The campus onboarding talks about, when exactly one is open. Otherwise the copy stays generic.
    private(set) var launchCampus: University?
    /// A notification opened the map and it should start on your sports.
    var focusMapOnMySports = false
    /// A link that arrived before the session was signed in.
    private(set) var pendingLink: URL?
    /// Sign-out hid the account, but the device token is still on the server. The saved session
    /// stays until the next launch or foreground can remove it.
    private(set) var signOutPendingUserID: UUID? {
        didSet { storePendingSignOut(signOutPendingUserID) }
    }

    @ObservationIgnored let auth: any AuthService
    @ObservationIgnored let push: PushNotificationService?
    @ObservationIgnored private let catalog: any AppConfigRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let signOutMarker: any SignOutMarker

    init(
        auth: any AuthService, catalog: any AppConfigRepository, push: PushNotificationService? = nil,
        defaults: UserDefaults = .standard, signOutMarker: any SignOutMarker = KeychainSignOutMarker()
    ) {
        self.auth = auth
        self.catalog = catalog
        self.push = push
        self.defaults = defaults
        self.signOutMarker = signOutMarker
        if let raw = defaults.string(forKey: Self.signOutPendingKey) ?? signOutMarker.read() {
            signOutPendingUserID = UUID(uuidString: raw)
        }
    }

    /// True when a sign-out is waiting to drop the token. Notification actions must not run as that account.
    static func isSignOutPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: signOutPendingKey) != nil || KeychainSignOutMarker().read() != nil
    }

    var session: Session {
        if isUpdateRequired { return .updateRequired }
        if let pending = signOutPendingUserID {
            switch auth.state {
            case .loading: return .launching
            case .suspended: return .suspended
            case .signedIn(let current) where current != pending: break
            default: return .onboarding
            }
        }
        switch auth.state {
        case .loading: return .launching
        case .signedOut, .pendingApproval, .needsProfile, .needsGuidelines: return .onboarding
        case .suspended: return .suspended
        case .signedIn: return .signedIn
        }
    }

    // MARK: Intents

    /// Version check, then the saved session. Offline, the built-in config lets the app carry on.
    func start() async {
        if let fetched = try? await catalog.fetchAppConfig() { config = fetched }
        isUpdateRequired = !config.supports(version: AppConfig.currentVersion)
        if let campuses = try? await catalog.fetchUniversities() {
            let open = campuses.filter(\.signupEnabled)
            if open.count == 1 { launchCampus = open[0] }
        }
        await auth.restoreSession()
        await finishPendingSignOutIfNeeded()
    }

    func presentGameForm(editing id: UUID? = nil) {
        sheet = .gameForm(editing: id)
    }

    func presentPlayAgain(_ id: UUID) {
        sheet = .playAgain(id)
    }

    /// "Count me in" away from the game's own screen: takes the spot right away (spots are
    /// first come, first served) and opens the game, where you're shown arriving.
    func joinAndOpen(_ id: UUID, in store: GameStore) {
        arrivingIn = id
        Task { await store.join(id) }
        path.append(.game(id))
    }

    /// The game's screen has shown you arriving.
    func finishArriving() {
        arrivingIn = nil
    }

    /// Back to the map from wherever you are ("Find a game").
    func showMap() {
        sheet = nil
        path = []
    }

    /// `masuno://game/<id>`, `masuno://game/<id>/chat` and `masuno://map`.
    /// A tap before sign-in waits until the session is ready.
    func handle(_ url: URL) {
        guard url.scheme == "masuno" else { return }
        guard session == .signedIn else {
            pendingLink = url
            return
        }
        open(url)
    }

    /// A notification tap, including one that waited through onboarding.
    /// A nil URL opens a link that was stored earlier.
    func deliverPushRoute(_ url: URL?) {
        if let url { handle(url) }
        openPendingLink()
    }

    /// Opens a link that arrived while the app was still launching or onboarding.
    func openPendingLink() {
        guard session == .signedIn, let url = pendingLink else { return }
        pendingLink = nil
        open(url)
    }

    func signOut(store: GameStore) async {
        let userID: UUID? = if case .signedIn(let id) = auth.state { id } else { nil }
        if let push, await push.unregister() == false {
            // The account leaves the screen now. The session stays so a later launch can drop the token.
            signOutPendingUserID = userID
            leaveAccount(store: store)
            return
        }
        signOutPendingUserID = nil
        do {
            try await auth.signOut()
            leaveAccount(store: store)
        } catch {
            store.notice = (error as? DomainError ?? .offline).message
        }
    }

    /// Sign-in reached the map. Stop trying to remove the token: this session should keep the phone.
    func noteSignInFinished() {
        signOutPendingUserID = nil
    }

    /// Removes a device token that sign-out could not, then ends the saved session.
    /// One call runs at a time. A sign-in that finishes while the token call is in flight is left alone.
    func finishPendingSignOutIfNeeded() async {
        if let existing = finishingSignOut {
            await existing.value
        }
        guard signOutPendingUserID != nil, finishingSignOut == nil else { return }
        let task = Task { @MainActor in
            await self.finishPendingSignOutNow()
            self.finishingSignOut = nil
        }
        finishingSignOut = task
        await task.value
    }

    @ObservationIgnored private var finishingSignOut: Task<Void, Never>?

    private func finishPendingSignOutNow() async {
        guard let pending = signOutPendingUserID else { return }
        if case .loading = auth.state { return }
        guard case .signedIn(let current) = auth.state, current == pending else {
            if case .signedIn = auth.state { signOutPendingUserID = nil }
            return
        }
        guard await push?.unregister() != false else { return }
        guard signOutPendingUserID == pending else { return }
        guard case .signedIn(let still) = auth.state, still == pending else { return }
        do {
            try await auth.signOut()
            if signOutPendingUserID == pending { signOutPendingUserID = nil }
        } catch {
            // The token is gone. The session is retried the next time the app opens.
        }
    }

    func deleteAccount(store: GameStore) async {
        await push?.unregister()
        do {
            try await auth.deleteAccount()
            // The server cascades the token. Clear this phone even if unregister did not.
            push?.discardLocalDevice()
            leaveAccount(store: store)
        } catch {
            store.notice = (error as? DomainError ?? .offline).message
        }
    }

    private func open(_ url: URL) {
        sheet = nil
        if url.host() == "map" {
            path = []
            focusMapOnMySports = true
            return
        }
        guard url.host() == "game" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let id = parts.compactMap(UUID.init(uuidString:)).first ?? UUID(uuidString: url.lastPathComponent) else { return }
        if parts.contains("chat") {
            path = [.game(id), .chat(id)]
        } else {
            path = [.game(id)]
        }
    }

    private static let signOutPendingKey = "signOutPendingUser"

    private func storePendingSignOut(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Self.signOutPendingKey)
        } else {
            defaults.removeObject(forKey: Self.signOutPendingKey)
        }
        signOutMarker.write(id?.uuidString)
    }

    private func leaveAccount(store: GameStore) {
        sheet = nil
        path = []
        store.reset()
    }

    #if DEBUG
    /// `-screen update|suspended|signed-out|session-expired|onboarding-*`: set before the session is read.
    func applyDebugSession(mock: MockBackend) {
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        switch screen {
        case "update": isUpdateRequired = true
        case "suspended": mock.suspend()
        case "signed-out": mock.endSession(expired: false)
        case "session-expired": mock.endSession(expired: true)
        case _ where screen.hasPrefix("onboarding-"): mock.endSession(expired: false)
        default: break
        }
    }

    /// Jump straight to a screen for design review, e.g. launch with `-screen me`. Options:
    /// me, me-hosting, me-past, me-empty, me-cancelled, me-leave, repost, profile, settings, sign-out, delete-account,
    /// add, add-filled, form-error, edit, cancel-game, play-again, picker, gallery, detail-*,
    /// join, spot-alert, who, block, report, report-sent, invite, leave, blocked, calendar, chat, chat-host, chat-rules,
    /// chat-new, chat-long, meetup, saved, filter, search, location, popup, popup-saved
    /// (popup, filter, search and location are handled by the map).
    func openDebugScreen(store: GameStore, mock: MockBackend) async {
        typealias IDs = MockFixtures.GameID
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        switch screen {
        case "me": path = [.me()]
        case "me-hosting": path = [.me(.hosting)]
        case "repost":
            // A player just dropped out of a full hosted game and auto-repost fired.
            mock.fillGame(id: IDs.hosting)
            mock.simulateDropOut(id: IDs.hosting)
            await store.refreshMyGames()
            path = [.me(.hosting)]
        case "profile": path = [.me(.going, editsProfile: true)]
        case "settings": path = [.me(), .settings]
        case "add", "add-filled", "form-error", "picker": presentGameForm()
        case "edit": presentGameForm(editing: IDs.hosting)
        case "gallery": path = [.gallery]
        case "chat": path = [.chat(IDs.going)]
        case "chat-rules":
            // First time in a chat: "Before you chat" comes up over it.
            mock.resetChatRules()
            await store.load()
            path = [.chat(IDs.going)]
        case "chat-long":
            // A busy chat on a slow connection: opens at the newest message, with "Earlier messages" above.
            for index in 1...60 {
                mock.now += 1
                mock.receiveMessage(from: index.isMultiple(of: 3) ? MockFixtures.maya : MockFixtures.sam, in: IDs.going, body: "Message \(index)")
            }
            mock.latency = .milliseconds(400)
            path = [.chat(IDs.going)]
        case "chat-new":
            // Someone wrote while you were away: "Group chat · 1 new" on the Going card.
            mock.receiveMessage(from: MockFixtures.sam, in: IDs.going, body: "Courts are free, come early if you can")
            await store.refreshUnread()
            path = [.me()]
        case "chat-host", "meetup": path = [.chat(IDs.hosting)]
        case "who", "report", "report-sent", "block", "invite": path = [.game(IDs.open)]
        case "leave": path = [.game(IDs.going)]
        case "me-leave", "me-past": path = [.me()]
        case "me-empty":
            // Nothing coming up: leave the one game the fixtures put you in.
            await store.leave(IDs.going)
            path = [.me()]
        case "me-cancelled":
            mock.cancelAsHost(id: IDs.going)
            await store.refreshMyGames()
            path = [.me()]
        case "sign-out", "delete-account": path = [.me(), .settings]
        case "cancel-game": presentGameForm(editing: IDs.hosting)
        case "play-again": presentPlayAgain(IDs.ended)
        case "spot-alert":
            if !store.hasSpotAlert(IDs.full) { store.toggleSpotAlert(IDs.full) }
            path = [.game(IDs.full)]
        case "blocked":
            await store.block(MockFixtures.sam)
            path = [.me(), .settings, .blockedPeople]
        case "calendar": path = [.game(IDs.going)]
        case "detail-open": path = [.game(IDs.open)]
        case "join":
            // "Count me in" on the map, once it has settled.
            try? await Task.sleep(for: .seconds(1.5))
            joinAndOpen(IDs.open, in: store)
        case "detail-in": path = [.game(IDs.going)]
        case "detail-full": path = [.game(IDs.full)]
        case "detail-hosting": path = [.game(IDs.hosting)]
        case "detail-ended": path = [.game(IDs.ended)]
        case "detail-cancelled": path = [.game(IDs.cancelled)]
        case "saved", "popup-saved":
            if !store.isSaved(IDs.lastSpot) { store.toggleSaved(IDs.lastSpot) }
            if screen == "saved", !store.hasSpotAlert(IDs.full) { store.toggleSpotAlert(IDs.full) }
            store.notice = nil
        default: break
        }
    }
    #endif
}
