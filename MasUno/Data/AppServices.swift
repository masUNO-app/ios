import Foundation

/// The one place that chooses what's behind the protocols. Mock ↔ live is a change here (B7).
struct AppServices {
    let auth: any AuthService
    let games: any GameRepository
    let profiles: any ProfileRepository
    let safety: any SafetyRepository
    let chat: any ChatRepository
    let catalog: any AppConfigRepository
    let notifications: any NotificationRepository
    let push: PushNotificationService
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
        let notificationSystem = MockNotificationSystemClient()
        // Exercise navigation while the system's notification-settings reply is delayed.
        notificationSystem.settingsDelay = .seconds(max(0, defaults.double(forKey: "notificationSettingsDelay")))
        let push = PushNotificationService(repository: mock, games: mock, chat: mock, system: notificationSystem)
        return AppServices(
            auth: mock, games: mock, profiles: mock, safety: mock, chat: mock, catalog: mock,
            notifications: mock, push: push, mock: mock
        )
        #else
        // Without real keys, every call fails as offline, so Release never shows mock data (N27).
        guard let live = LiveBackend.make() else {
            let backend = UnavailableBackend()
            let push = PushNotificationService(repository: backend, games: backend, chat: backend)
            return AppServices(
                auth: backend, games: backend, profiles: backend, safety: backend, chat: backend,
                catalog: backend, notifications: backend, push: push
            )
        }
        return AppServices(live)
        #endif
    }
}

/// One set of services for the process, including a background launch that never opens a scene.
enum AppLaunch {
    static let services = AppServices.make()
}

private extension AppServices {
    #if DEBUG
    init(_ live: LiveBackend, mock: MockBackend) {
        let push = PushNotificationService(repository: live.notifications, games: live.games, chat: live.chat)
        self.init(
            auth: live.auth, games: live.games, profiles: live.profiles, safety: live.safety, chat: live.chat,
            catalog: live.catalog, notifications: live.notifications, push: push, mock: mock
        )
    }
    #else
    init(_ live: LiveBackend) {
        let push = PushNotificationService(repository: live.notifications, games: live.games, chat: live.chat)
        self.init(
            auth: live.auth, games: live.games, profiles: live.profiles, safety: live.safety, chat: live.chat,
            catalog: live.catalog, notifications: live.notifications, push: push
        )
    }
    #endif
}
