import Foundation

/// The project this build talks to, from `Config.xcconfig` by way of Info.plist.
nonisolated struct SupabaseConfig: Hashable, Sendable {
    let url: URL
    let anonKey: String

    /// `nil` for the template's placeholders, so a build without real keys never calls out.
    init?(url: String?, anonKey: String?) {
        guard let url, let anonKey, !anonKey.isEmpty,
              !url.contains("YOUR-"), !anonKey.contains("YOUR-"), !url.contains("$("), !anonKey.contains("$("),
              let parsed = URL(string: url), parsed.scheme == "https", parsed.host() != nil
        else { return nil }
        self.url = parsed
        self.anonKey = anonKey
    }

    static var current: SupabaseConfig? {
        SupabaseConfig(
            url: Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            anonKey: Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        )
    }
}
