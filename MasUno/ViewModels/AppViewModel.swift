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
        case .signedOut, .needsProfile, .needsGuidelines: return .onboarding
        case .suspended: return .suspended
        case .signedIn: return .signedIn
        }
    }

    // MARK: Intents

    /// Version check, then the saved session. Offline, the built-in config lets the app carry on.
    func start() async {
        if let fetched = try? await catalog.fetchAppConfig() { config = fetched }
        isUpdateRequired = !config.supports(version: AppConfig.currentVersion)
        if let open = try? await catalog.fetchOpenUniversities(), open.count == 1 { launchCampus = open[0] }
        await auth.restoreSession()
    }

    func presentGameForm(editing id: UUID? = nil) {
        sheet = .gameForm(editing: id)
    }

    /// `masuno://game/<id>` → Event detail (2.0 notifications use this).
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
    /// `-screen update|suspended|signed-out|onboarding-*`: set before the session is read.
    func applyDebugSession(mock: MockBackend) {
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        switch screen {
        case "update": isUpdateRequired = true
        case "suspended": mock.suspend()
        case "signed-out": mock.expireSession(email: nil)
        case _ where screen.hasPrefix("onboarding-"): mock.expireSession(email: nil)
        default: break
        }
    }

    /// Jump straight to a screen for design review, e.g. launch with `-screen me`. Options:
    /// me, me-hosting, repost, profile, settings, add, add-filled, form-error, edit, picker, gallery,
    /// detail-*, who, report, blocked, calendar, chat, chat-host, meetup, saved, popup, popup-saved
    /// (popup is handled in `EventMapViewModel`).
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
        case "chat-host", "meetup": path = [.chat(IDs.hosting)]
        case "who", "report": path = [.game(IDs.open)]
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
        default: break
        }
    }
    #endif
}
