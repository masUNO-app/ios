import Foundation

/// The one place that chooses what's behind the protocols. Mock ↔ live is a change here (B7).
struct AppServices {
    let auth: any AuthService
    let games: any GameRepository
    let profiles: any ProfileRepository
    let safety: any SafetyRepository
    let catalog: any AppConfigRepository
    #if DEBUG
    let mock: MockBackend
    #endif

    static func make() -> AppServices {
        #if DEBUG
        let mock = MockBackend()
        // `-raceJoin YES`: someone else takes the last spot while your join is in flight.
        mock.losesNextJoinRace = UserDefaults.standard.bool(forKey: "raceJoin")
        // `-liveAuth YES`: real sign-in on `masuno-dev`, with games still on mocks until B7.
        if UserDefaults.standard.bool(forKey: "liveAuth"), let live = LiveBackend.make() {
            return AppServices(auth: live.auth, games: mock, profiles: mock, safety: mock, catalog: live.catalog, mock: mock)
        }
        return AppServices(auth: mock, games: mock, profiles: mock, safety: mock, catalog: mock, mock: mock)
        #else
        // TODO(B7): the live game, profile and safety repositories go here.
        let backend = UnavailableBackend()
        guard let live = LiveBackend.make() else {
            return AppServices(auth: backend, games: backend, profiles: backend, safety: backend, catalog: backend)
        }
        return AppServices(auth: live.auth, games: backend, profiles: backend, safety: backend, catalog: live.catalog)
        #endif
    }
}
