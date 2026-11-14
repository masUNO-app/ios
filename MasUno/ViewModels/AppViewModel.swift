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
            case .join: String(localized: "Join with a student account")
            case .save: String(localized: "Save games with an account")
            case .host: String(localized: "Host with a student account")
            case .whosGoing: String(localized: "See who's going")
            case .me: String(localized: "Your account")
            case .report: String(localized: "Report with an account")
            }
        }

        /// One or two sentences under the title.
        var message: String {
            switch self {
            case .join:
                String(localized: "Create an account with your school email so other players know you're a real student. Takes about a minute.")
            case .save:
                String(localized: "Bookmarks and spot alerts stay on your account. Create one with your school email to keep games for later.")
            case .host:
                String(localized: "Only verified students can post a game. Create an account with your school email to host.")
            case .whosGoing:
                String(localized: "Names stay with verified students. Create an account with your school email to see who's going.")
            case .me:
                String(localized: "Create an account with your school email, or sign in if you already have one.")
            case .report:
                String(localized: "Reporting needs a student account so we can follow up. Create one with your school email.")
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

    @ObservationIgnored let auth: any AuthService
    @ObservationIgnored private let catalog: any AppConfigRepository
    @ObservationIgnored private let defaults: UserDefaults
    private static let guestCampusKey = "guestCampus"

    init(auth: any AuthService, catalog: any AppConfigRepository, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.catalog = catalog
        self.defaults = defaults
        guestCampus = defaults.data(forKey: Self.guestCampusKey).flatMap { try? JSONDecoder().decode(University.self, from: $0) }
    }

    var session: Session {
        if isUpdateRequired { return .updateRequired }
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
        if let fetched = try? await catalog.fetchAppConfig() { config = fetched }
        isUpdateRequired = !config.supports(version: AppConfig.currentVersion)
        if let campuses = try? await catalog.fetchUniversities() {
            let open = campuses.filter(\.signupEnabled)
            openCampusCount = open.count
            if open.count == 1 { launchCampus = open[0] }
            // A returning guest's campus may have closed since; if so, they start at Welcome.
            if let browsing = guestCampus { guestCampus = open.first { $0.id == browsing.id } }
        }
        await auth.restoreSession()
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

    /// `masuno://game/<id>` → Event detail (1.0 notifications use this).
    func handle(_ url: URL) {
        guard url.scheme == "masuno", url.host() == "game",
              let id = UUID(uuidString: url.lastPathComponent) else { return }
        sheet = nil
        path = [.game(id)]
    }

    func signOut(store: GameStore) async {
        do {
            try await auth.signOut()
            leaveAccount(store: store)
        } catch {
            store.notice = (error as? DomainError ?? .offline).message
        }
    }

    func deleteAccount(store: GameStore) async {
        do {
            try await auth.deleteAccount()
            leaveAccount(store: store)
        } catch {
            store.notice = (error as? DomainError ?? .offline).message
        }
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
    /// guest campus step with two campuses open): set before the session is read.
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
    /// me, me-hosting, me-past, me-empty, me-cancelled, me-leave, repost, profile, settings, sign-out, delete-account,
    /// add, add-filled, form-error, edit, cancel-game, play-again, picker, gallery, detail-*,
    /// join, spot-alert, who, block, report, report-sent, invite, leave, blocked, calendar, chat, chat-host, chat-rules,
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
