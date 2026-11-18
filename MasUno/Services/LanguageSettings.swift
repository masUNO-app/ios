import Foundation
import Observation

/// One language choice for SwiftUI, formatted strings, sport names and push registration.
@Observable
final class LanguageSettings {
    enum Preference: String, CaseIterable, Identifiable {
        case system, en, es
        var id: Self { self }
    }

    static let shared = LanguageSettings()
    static let preferenceKey = "appLanguage"

    var preference: Preference {
        didSet { defaults.set(preference.rawValue, forKey: Self.preferenceKey) }
    }
    private(set) var deviceLanguage: String
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        preference = Preference(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        deviceLanguage = Self.supportedLanguage(preferredLanguages.first)
    }

    var language: String { preference == .system ? deviceLanguage : preference.rawValue }

    var locale: Locale {
        // Keep the person's region for date/number conventions and measurement units.
        Locale(identifier: "\(language)-\(Locale.autoupdatingCurrent.region?.identifier ?? "US")")
    }

    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    func refreshDeviceLanguage(preferredLanguages: [String] = Locale.preferredLanguages) {
        deviceLanguage = Self.supportedLanguage(preferredLanguages.first)
    }

    private static func supportedLanguage(_ identifier: String?) -> String {
        Locale(identifier: identifier ?? "en").language.languageCode?.identifier == "es" ? "es" : "en"
    }
}
