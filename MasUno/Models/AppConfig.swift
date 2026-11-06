import Foundation

/// Values from the `app_config` table (SPEC §8.3).
struct AppConfig: Hashable {
    /// Older builds see "Update masUNO" (E3).
    var minSupportedVersion: String
    var supportEmail: String
    /// Privacy & Terms page — set once Arianna's website pages are up (D4).
    var privacyURL: URL?

    /// Used until the real values load, and if they can't.
    static let fallback = AppConfig(minSupportedVersion: "0.1", supportEmail: "masunoapp@gmail.com", privacyURL: nil)

    /// App Store search, until the listing has an ID to link to directly.
    static let appStoreURL = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=masUNO")!

    /// TODO/TEMP(E19): the link "Invite a friend" shares. Swap for the App Store page once
    /// the listing exists (the TestFlight public link while in beta). Opening a specific game
    /// from the link needs Universal Links, which is after the program.
    static let inviteURL = URL(string: "https://apps.apple.com/search?term=masUNO")!

    var supportMailURL: URL? { URL(string: "mailto:\(supportEmail)") }

    /// Whether this build is at least `minSupportedVersion`.
    func supports(version: String) -> Bool {
        version.compare(minSupportedVersion, options: .numeric) != .orderedAscending
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
