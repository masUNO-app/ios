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
    private(set) var config = AppConfig.fallback
    private(set) var isUpdateRequired = false
    /// The campus onboarding talks about, when exactly one is open. Otherwise the copy stays generic.
    private(set) var launchCampus: University?

    @ObservationIgnored let auth: any AuthService
    @ObservationIgnored private let catalog: any AppConfigRepository

    init(auth: any AuthService, catalog: any AppConfigRepository) {
        self.auth = auth
        self.catalog = catalog
    }

    var session: Session {
        if isUpdateRequired { return .updateRequired }
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
    }

    func presentGameForm(editing id: UUID? = nil) {
        sheet = .gameForm(editing: id)
    }

    func presentPlayAgain(_ id: UUID) {
        sheet = .playAgain(id)
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
    /// spot-alert, who, block, report, report-sent, invite, leave, blocked, calendar, chat, chat-host, chat-rules,
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
