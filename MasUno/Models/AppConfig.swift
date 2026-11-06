import Foundation

/// Values from the `app_config` table (SPEC §8.3).
struct AppConfig: Hashable {
    /// Older builds see "Update masUNO" (E3).
    var minSupportedVersion: String
    var supportEmail: String
    /// Privacy & Terms page (D4).
    var privacyURL: URL

    /// Used until the real values load, and if they can't.
    static let fallback = AppConfig(
        minSupportedVersion: "1.0", supportEmail: "masunoapp@gmail.com",
        privacyURL: URL(string: "https://masuno-app.github.io/privacy")!
    )

    /// TODO(E15): the Apple ID from App Store Connect. Until it's set, Release hides
    /// "Invite a friend" rather than share a search link (N27, SPEC §10.4).
    static let appStoreID: String? = nil

    /// "Update masUNO": the listing if we know it, otherwise an App Store search.
    static var appStoreURL: URL {
        appStoreID.flatMap { URL(string: "itms-apps://apps.apple.com/app/id\($0)") }
            ?? URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=masUNO")!
    }

    /// The link "Invite a friend" shares. Opening a specific game from it needs Universal Links,
    /// which is after the program.
    static var inviteURL: URL? {
        if let appStoreID { return URL(string: "https://apps.apple.com/app/id\(appStoreID)") }
        #if DEBUG
        return URL(string: "https://apps.apple.com/search?term=masUNO")
        #else
        return nil
        #endif
    }

    var supportMailURL: URL? { URL(string: "mailto:\(supportEmail)") }

    /// Whether this build is at least `minSupportedVersion`.
    func supports(version: String) -> Bool {
        version.compare(minSupportedVersion, options: .numeric) != .orderedAscending
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
