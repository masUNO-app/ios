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
        didSet {
            defaults.set(preference.rawValue, forKey: Self.preferenceKey)
            resolve()
        }
    }
    private(set) var deviceLanguage: String
    /// The `.lproj` for `language`, or `.main` if it's missing. Updated by `resolve()`.
    private(set) var bundle: Bundle = .main
    /// `language` with the person's region, for date/number conventions and measurement units.
    /// Updated by `resolve()`.
    private(set) var locale: Locale = .current
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        preference = Preference(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        deviceLanguage = Self.supportedLanguage(preferredLanguages.first)
        resolve()
        // A region change in iOS Settings also arrives through `refreshDeviceLanguage()` when the app
        // becomes active; this catches it if it lands while the app is running.
        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resolve() }
        }
    }

    var language: String { preference == .system ? deviceLanguage : preference.rawValue }

    func refreshDeviceLanguage(preferredLanguages: [String] = Locale.preferredLanguages) {
        deviceLanguage = Self.supportedLanguage(preferredLanguages.first)
        // Also picks up a region change made in iOS Settings while the app was in the background.
        resolve()
    }

    /// Recomputes `bundle` and `locale` from `language`. Only assigns on a real change, so views that
    /// read them aren't invalidated for nothing.
    private func resolve() {
        let language = language
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let locale = Locale(identifier: "\(language)-\(Locale.autoupdatingCurrent.region?.identifier ?? "US")")
        if bundle != self.bundle { self.bundle = bundle }
        if locale != self.locale { self.locale = locale }
    }

    private static func supportedLanguage(_ identifier: String?) -> String {
        Locale(identifier: identifier ?? "en").language.languageCode?.identifier == "es" ? "es" : "en"
    }
}

extension String {
    /// `String(localized:)` in the app's language (Settings › Language), not just the device's.
    /// Use this for every formatted string built outside a `Text`.
    static func app(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
    }
}
