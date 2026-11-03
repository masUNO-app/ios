import Foundation

/// Values from the `app_config` table (SPEC §8.3). Mocked until the live repositories land (B7).
struct AppConfig: Hashable {
    /// Older builds see "Update masUNO" (E3).
    var minSupportedVersion: String
    var supportEmail: String
    /// Privacy & Terms page — set once Arianna's website pages are up (D4).
    var privacyURL: URL?

    static let mock = AppConfig(minSupportedVersion: "0.1", supportEmail: "masunoapp@gmail.com", privacyURL: nil)

    /// App Store search, until the listing has an ID to link to directly.
    static let appStoreURL = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=masUNO")!

    var supportMailURL: URL? { URL(string: "mailto:\(supportEmail)") }

    /// Whether this build is at least `minSupportedVersion`.
    func supports(version: String) -> Bool {
        version.compare(minSupportedVersion, options: .numeric) != .orderedAscending
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
