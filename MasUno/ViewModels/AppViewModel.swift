import Foundation
import Observation

/// Root presentation state (SPEC §7.3): the launch gate, the navigation path and
/// app-level sheets. Sheets that open on top of a screen or another sheet
/// (location picker, Who's going, report) are presented by that screen.
@Observable
final class AppViewModel {
    /// Where launch lands: version check → session → Map.
    enum Session: Equatable {
        case updateRequired
        case signedOut
        case suspended
        case signedIn
    }

    enum Sheet: Identifiable, Hashable {
        case gameForm(editing: SportsEvent.ID?)

        var id: Self { self }
    }

    var session: Session
    var path: [Route] = []
    var sheet: Sheet?
    let config: AppConfig

    /// TODO(E5/B5): start from `AuthService`'s session; mock auth is always signed in.
    init(config: AppConfig = .mock, version: String = AppConfig.currentVersion) {
        self.config = config
        session = config.supports(version: version) ? .signedIn : .updateRequired
    }

    // MARK: Intents

    func presentGameForm(editing id: SportsEvent.ID? = nil) {
        sheet = .gameForm(editing: id)
    }

    /// `masuno://game/<id>` → Event detail (2.0 notifications use this).
    func handle(_ url: URL) {
        guard url.scheme == "masuno", url.host() == "game",
              let id = UUID(uuidString: url.lastPathComponent) else { return }
        sheet = nil
        path = [.game(id)]
    }

    /// TODO(B5): `AuthService.signOut()`.
    func signOut() {
        sheet = nil
        path = []
        session = .signedOut
    }

    /// TODO(E5): onboarding. Mock auth signs straight back in.
    func signIn() {
        session = .signedIn
    }

    #if DEBUG
    /// Jump straight to a screen for design review, e.g. launch with `-screen me`.
    /// Options: update, signed-out, suspended, me, me-hosting, settings, add, form-error, edit,
    /// picker, gallery, detail-*, who, report, blocked, popup (handled in `EventMapViewModel`).
    func openDebugScreen(in store: EventStore) {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "update": session = .updateRequired
        case "signed-out": session = .signedOut
        case "suspended": session = .suspended
        case "me": path = [.me()]
        case "me-hosting": path = [.me(.hosting)]
        case "settings": path = [.me(), .settings]
        case "add", "form-error", "picker": presentGameForm()
        case "edit": presentGameForm(editing: store.hostedEvents.first?.id)
        case "gallery": path = [.gallery]
        case "who", "report": path = Self.debugDetailID("detail-open", in: store).map { [.game($0)] } ?? []
        case "blocked":
            store.block("Jordan Lee")
            path = [.me(), .settings, .blockedPeople]
        case let screen? where screen.hasPrefix("detail-"):
            if let id = Self.debugDetailID(screen, in: store) { path = [.game(id)] }
        default: break
        }
    }

    /// `-screen detail-open|in|full|hosting|ended|cancelled` (add `-raceJoin YES` to `detail-open`).
    private static func debugDetailID(_ screen: String, in store: EventStore) -> SportsEvent.ID? {
        let title = switch screen {
        case "detail-in": "Sunday soccer"
        case "detail-full": "Friday night 5v5"
        case "detail-hosting": "Volleyball night"
        case "detail-ended": "Morning shootaround"
        case "detail-cancelled": "Beach volleyball"
        default: "After-work hoops"
        }
        return store.events.first { $0.title == title }?.id
    }
    #endif
}
