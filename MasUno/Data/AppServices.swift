import Foundation

/// The one place that chooses what's behind the protocols. Mock ↔ live is a change here (B7).
struct AppServices {
    let auth: any AuthService
    let games: any GameRepository
    let profiles: any ProfileRepository
    let safety: any SafetyRepository
    let chat: any ChatRepository
    let catalog: any AppConfigRepository
    #if DEBUG
    let mock: MockBackend
    #endif

    static func make() -> AppServices {
        #if DEBUG
        let mock = MockBackend()
        // `-raceJoin YES`: someone else takes the last spot while your join is in flight.
        mock.losesNextJoinRace = UserDefaults.standard.bool(forKey: "raceJoin")
        // Everything on `masuno-dev` (Debug's keys in `Config.xcconfig`), unless `-liveAuth NO`. Launch
        // arguments only exist when Xcode launches the app, so a build opened from the home screen
        // has none: live is the default, and `-screen` (design review on fixtures) means mocks.
        let defaults = UserDefaults.standard
        let wantsLive = defaults.object(forKey: "liveAuth") != nil
            ? defaults.bool(forKey: "liveAuth")
            : defaults.string(forKey: "screen") == nil
        if wantsLive, let live = LiveBackend.make() {
            return AppServices(live, mock: mock)
        }
        return AppServices(auth: mock, games: mock, profiles: mock, safety: mock, chat: mock, catalog: mock, mock: mock)
        #else
        // Without real keys, every call fails as offline, so Release never shows mock data (N27).
        guard let live = LiveBackend.make() else {
            let backend = UnavailableBackend()
            return AppServices(auth: backend, games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend)
        }
        return AppServices(live)
        #endif
    }
}

private extension AppServices {
    #if DEBUG
    init(_ live: LiveBackend, mock: MockBackend) {
        self.init(auth: live.auth, games: live.games, profiles: live.profiles, safety: live.safety, chat: live.chat, catalog: live.catalog, mock: mock)
    }
    #else
    init(_ live: LiveBackend) {
        self.init(auth: live.auth, games: live.games, profiles: live.profiles, safety: live.safety, chat: live.chat, catalog: live.catalog)
    }
    #endif
}
