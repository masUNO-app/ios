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
        return AppServices(auth: mock, games: mock, profiles: mock, safety: mock, catalog: mock, mock: mock)
        #else
        // TODO(B5, B7): the live AuthService and repositories go here once the backend is up.
        let backend = UnavailableBackend()
        return AppServices(auth: backend, games: backend, profiles: backend, safety: backend, catalog: backend)
        #endif
    }
}
