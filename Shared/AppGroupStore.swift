import Foundation

/// The few values the app and the notification extension both need.
/// The suite is `group.com.masuno.app`. Without the entitlement (tests, a simulator
/// that hasn't signed it) this falls back to standard defaults so nothing crashes.
nonisolated enum AppGroupStore {
    static let suiteName = "group.com.masuno.app"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// The signed-in person's ID, so a chat notification can mark them as "me".
    static var myID: String? {
        get { defaults.string(forKey: "myID") }
        set { defaults.set(newValue, forKey: "myID") }
    }

    /// The chat currently on screen. A banner for this chat is hidden.
    /// Memory only: a killed app must not keep hiding that chat's banners.
    nonisolated(unsafe) static var openChatID: String?

    /// The game currently on screen. A banner for this game is hidden.
    nonisolated(unsafe) static var openGameID: String?

    /// Sign-out. The extension stops treating anyone as "me".
    static func clearAccount() {
        myID = nil
        openChatID = nil
        openGameID = nil
    }
}
