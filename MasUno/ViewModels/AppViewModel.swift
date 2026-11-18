import Foundation
import Observation
import UserNotifications

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
        /// Signed out, browsing open games without names (SPEC R7-15).
        case guest
        case suspended
        case signedIn
    }

    enum Sheet: Identifiable, Hashable {
        case gameForm(editing: UUID?)
        /// "Play again": a new game that starts from an earlier one's sport, place and details.
        case playAgain(UUID)

        var id: Self { self }
    }

    /// Why a guest was asked to make an account. One dialog covers join, save, host and Who's going.
    enum AccountPrompt: String, Identifiable {
        case join
        case save
        case host
        case whosGoing
        case me
        case report

        var id: String { rawValue }

        /// Title on the shared "continue onboarding" card.
        var title: String {
            switch self {
            case .join: String.app("Join with a student account")
            case .save: String.app("Save games with an account")
            case .host: String.app("Host with a student account")
            case .whosGoing: String.app("See who's going")
            case .me: String.app("Your account")
            case .report: String.app("Report with an account")
            }
        }

        /// One or two sentences under the title.
        var message: String {
            switch self {
            case .join:
                String.app("Create an account with your school email so other players know you're a real student. Takes about a minute.")
            case .save:
                String.app("Bookmarks and spot alerts stay on your account. Create one with your school email to keep games for later.")
            case .host:
                String.app("Only verified students can post a game. Create an account with your school email to host.")
            case .whosGoing:
                String.app("Names stay with verified students. Create an account with your school email to see who's going.")
            case .me:
                String.app("Create an account with your school email, or sign in if you already have one.")
            case .report:
                String.app("Reporting needs a student account so we can follow up. Create one with your school email.")
            }
        }
    }

    /// After leaving guest browse, onboarding opens this step (Create account or Sign in).
    enum OnboardingResume: Equatable {
        case signUp
        case signIn
        /// "Browse another campus": the campus step.
        case guestCampus
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
    /// How many campuses are open. A guest can switch campus only when there's more than one.
    private(set) var openCampusCount = 0
    var canSwitchGuestCampus: Bool { openCampusCount > 1 }
    /// The campus a guest is browsing (SPEC R7-15). Kept on the phone, so a guest who comes back
    /// lands on the map again instead of Welcome. Cleared when they go to create an account or
    /// sign in, and once an account is signed in.
    private(set) var guestCampus: University? {
        didSet { defaults.set(guestCampus.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.guestCampusKey) }
    }
    /// Signed out and browsing the map as a guest.
    var isBrowsingAsGuest: Bool { guestCampus != nil }
    /// Guest tapped join / save / host / … — the shared account card.
    var accountPrompt: AccountPrompt?
    /// Consumed by `OnboardingFlow` after leaving guest browse.
    private(set) var onboardingResume: OnboardingResume?
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
    private static let guestCampusKey = "guestCampus"
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
        guestCampus = defaults.data(forKey: Self.guestCampusKey).flatMap { try? JSONDecoder().decode(University.self, from: $0) }
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
        case .signedOut where isBrowsingAsGuest: return .guest
        case .signedOut, .pendingApproval, .needsProfile, .needsGuidelines: return .onboarding
        case .suspended: return .suspended
        case .signedIn: return .signedIn
        }
    }

    // MARK: Intents

    /// Version check, then the saved session. Offline, the built-in config lets the app carry on.
    func start() async {
        let fetchedConfig = Task { @MainActor [catalog] in try? await catalog.fetchAppConfig() }
        let fetchedCampuses = Task { @MainActor [catalog] in try? await catalog.fetchUniversities() }
        defer { fetchedConfig.cancel(); fetchedCampuses.cancel() }
        if let fetched = await fetchedConfig.value { config = fetched }
        isUpdateRequired = !config.supports(version: AppConfig.currentVersion)
        await auth.restoreSession()
        if let campuses = await fetchedCampuses.value {
            let open = campuses.filter(\.signupEnabled)
            openCampusCount = open.count
            if open.count == 1 { launchCampus = open[0] }
            // A returning guest's campus may have closed since; if so, they start at Welcome.
            if let browsing = guestCampus { guestCampus = open.first { $0.id == browsing.id } }
        }
        await finishPendingSignOutIfNeeded()
        // An account always wins over a leftover guest choice.
        if case .signedIn = auth.state { guestCampus = nil }
    }

    /// A returning guest: reload the campus they were browsing. Call once `start()` has run.
    func resumeGuestBrowsing(store: GameStore) async {
        guard session == .guest, let guestCampus else { return }
        await store.loadGuest(campus: guestCampus)
    }

    func presentGameForm(editing id: UUID? = nil) {
        if isBrowsingAsGuest { return requireAccount(.host) }
        sheet = .gameForm(editing: id)
    }

    func presentPlayAgain(_ id: UUID) {
        if isBrowsingAsGuest { return requireAccount(.host) }
        sheet = .playAgain(id)
    }

    /// "Count me in" away from the game's own screen: takes the spot right away (spots are
    /// first come, first served) and opens the game, where you're shown arriving.
    func joinAndOpen(_ id: UUID, in store: GameStore) {
        if isBrowsingAsGuest { return requireAccount(.join) }
        arrivingIn = id
        Task { await store.join(id) }
        path.append(.game(id))
    }

    /// Opens the map for a signed-out person on one campus (`GameStore.loadGuest`).
    /// - Parameter campus: An open campus from `university_lookup` (not the hidden demo).
    /// - Parameter store: Clears any prior guest preview and loads that campus's games.
    func browseAsGuest(campus: University, store: GameStore) async {
        accountPrompt = nil
        onboardingResume = nil
        path = []
        sheet = nil
        guestCampus = campus
        await store.loadGuest(campus: campus)
    }

    /// Leaves guest browse and returns to onboarding. Optionally opens Create account or Sign in.
    /// - Parameter resume: The step Welcome should jump to, or `nil` for Welcome itself.
    /// - Parameter store: Cleared so nameless games don't linger.
    func endGuestBrowsing(resume: OnboardingResume? = nil, store: GameStore) {
        accountPrompt = nil
        onboardingResume = resume
        path = []
        sheet = nil
        guestCampus = nil
        store.reset()
    }

    /// Guest tried an account-only action: show the shared continue-onboarding card.
    /// - Parameter prompt: Which action they tried (copy only).
    func requireAccount(_ prompt: AccountPrompt) {
        guard isBrowsingAsGuest else { return }
        accountPrompt = prompt
    }

    /// Onboarding consumed `onboardingResume` (Create account / Sign in after guest browse).
    func clearOnboardingResume() {
        onboardingResume = nil
    }

    /// Drops guest chrome when the account is signed in. Does not reset the store — `load()` does.
    func clearGuestBrowsingFlag() {
        guestCampus = nil
        accountPrompt = nil
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
        if let url {
            pendingLink = nil
            handle(url)
        }
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
        if case .signedIn(let id) = auth.state { push?.noteAccount(id) }
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
        guestCampus = nil
        accountPrompt = nil
        onboardingResume = nil
        store.reset()
    }

    #if DEBUG
    /// `-screen update|suspended|signed-out|session-expired|guest|onboarding-*` (`onboarding-campus` opens the
    /// guest campus step with two campuses open; `onboarding-pending` and `onboarding-pending-code` sign up a
    /// mock account first, so it is really on the waitlist): set before the session is read.
    func applyDebugSession(mock: MockBackend) {
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        // A guest choice left over from an earlier run would open the map instead of the screen asked for.
        if !screen.isEmpty, !screen.hasPrefix("guest") { guestCampus = nil }
        switch screen {
        case "update": isUpdateRequired = true
        case "suspended": mock.suspend()
        case "signed-out": mock.endSession(expired: false)
        case "session-expired": mock.endSession(expired: true)
        case "onboarding-campus":
            // Two open campuses, so Browse as a guest asks which one.
            mock.universities = [MockFixtures.tec, MockFixtures.otherCampus]
            launchCampus = nil
            openCampusCount = 2
            mock.endSession(expired: false)
        case _ where screen.hasPrefix("guest") || screen.hasPrefix("onboarding-"): mock.endSession(expired: false)
        default: break
        }
    }

    /// Jump straight to a screen for design review, e.g. launch with `-screen me`. Options:
    /// map (the map on fixtures, as any value not listed here), me, invites (Me with the Invites sheet open), me-hosting, me-past, me-empty, me-cancelled, me-leave, repost, profile, settings, sign-out, delete-account,
    /// add, add-filled, form-error, edit, cancel-game, play-again, picker, gallery, detail-*,
    /// join, spot-alert, who, who-beta (a game with two beta testers), block, report, report-sent, invite, leave, blocked, calendar, chat, chat-host, chat-rules,
    /// chat-new, chat-long, meetup, saved, filter, search, location, popup, popup-saved, guest, guest-popup,
    /// guest-detail, guest-prompt (popup, guest-popup, filter, search and location are handled by the map).
    func openDebugScreen(store: GameStore, mock: MockBackend) async {
        typealias IDs = MockFixtures.GameID
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        switch screen {
        case "guest", "guest-popup", "guest-detail", "guest-prompt":
            await browseAsGuest(campus: launchCampus ?? MockFixtures.tec, store: store)
            if screen == "guest-detail" { path = [.game(IDs.open)] }
            if screen == "guest-prompt" { requireAccount(.join) }
        case "me", "invites": path = [.me()]
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
        case "push-chat", "push-game":
            await push?.handle(
                action: UNNotificationDefaultActionIdentifier,
                payload: NotificationPayload(kind: screen == "push-chat" ? "chat_message" : "reminder", gameID: IDs.going),
                reply: nil
            )
        case "chat-unavailable": path = [.chat(IDs.open)]
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
        case "who-beta": path = [.game(IDs.lastSpot)]
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
        case "create-primer":
            // Deterministic UI regression for the success path that used to crash in the primer.
            guard let template = store.game(IDs.open) else { return }
            var draft = GameDraft(template)
            draft.title = "Primer regression game"
            draft.startsAt = .now.addingTimeInterval(7200)
            try? await store.createGame(draft)
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
