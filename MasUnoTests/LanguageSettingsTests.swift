import Foundation
import Testing
@testable import masUNO

@MainActor
struct LanguageSettingsTests {
    private let defaults = UserDefaults(suiteName: "LanguageTests.\(UUID().uuidString)")!

    @Test func spanishDeviceUsesSpanish() {
        for identifier in ["es", "es-MX", "es-ES", "es_US"] {
            let settings = LanguageSettings(defaults: defaults, preferredLanguages: [identifier])
            #expect(settings.preference == .system)
            #expect(settings.language == "es")
        }
    }

    @Test func everyOtherPrimaryLanguageFallsBackToEnglish() {
        for languages in [["en-US"], ["fr-FR", "es-MX"], ["de-DE"], ["ja-JP"], []] {
            #expect(LanguageSettings(defaults: defaults, preferredLanguages: languages).language == "en")
        }
    }

    @Test func overridePersistsAndDeviceModeCanBeRestored() {
        let first = LanguageSettings(defaults: defaults, preferredLanguages: ["en-US"])
        first.preference = .es
        let relaunched = LanguageSettings(defaults: defaults, preferredLanguages: ["en-US"])
        #expect(relaunched.preference == .es)
        #expect(relaunched.language == "es")
        relaunched.refreshDeviceLanguage(preferredLanguages: ["fr-FR"])
        #expect(relaunched.language == "es")
        relaunched.preference = .system
        #expect(relaunched.language == "en")
        relaunched.refreshDeviceLanguage(preferredLanguages: ["es-MX"])
        #expect(relaunched.language == "es")
        relaunched.preference = .en
        #expect(relaunched.language == "en")
    }

    @Test func unknownStoredChoiceUsesDeviceLanguage() {
        defaults.set("unsupported", forKey: LanguageSettings.preferenceKey)
        #expect(LanguageSettings(defaults: defaults, preferredLanguages: ["es-MX"]).language == "es")
    }

    @Test func formattedStringsUseSelectedBundleAndSpanishPlurals() {
        let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["en-US"])
        settings.preference = .es
        #expect(String(localized: "Settings", bundle: settings.bundle, locale: settings.locale) == "Ajustes")
        let one = 1, two = 2
        #expect(String(localized: "\(one) players", bundle: settings.bundle, locale: settings.locale) == "1 jugador")
        #expect(String(localized: "\(two) players", bundle: settings.bundle, locale: settings.locale) == "2 jugadores")
        settings.preference = .en
        #expect(String(localized: "Settings", bundle: settings.bundle, locale: settings.locale) == "Settings")
    }

    @Test func everyCatalogEntryHasSpanishAndPreservesFormatArguments() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "MasUno/Localizable.xcstrings"))
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let pattern = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:lld|ld|d|@|f)"#)
        func arguments(_ value: String) -> [String] {
            pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
                String(value[Range(match.range, in: value)!]).replacingOccurrences(of: #"%[0-9]+\$"#, with: "%", options: .regularExpression)
            }.sorted()
        }
        func units(_ value: [String: Any]) -> [[String: String]] {
            if let unit = value["stringUnit"] as? [String: String] { return [unit] }
            return value.values.flatMap { child in (child as? [String: Any]).map(units) ?? [] }
        }
        for (key, entry) in strings {
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]], "Missing localization: \(key)")
            let spanish = try #require(localizations["es"], "Missing Spanish: \(key)")
            let translations = units(spanish)
            #expect(!translations.isEmpty, "Missing Spanish text: \(key)")
            let english = units(localizations["en"] ?? [:]).first?["value"] ?? key
            for unit in translations {
                #expect(unit["state"] == "translated", "Unfinished Spanish: \(key)")
                let text = try #require(unit["value"])
                #expect(!text.isEmpty, "Empty Spanish: \(key)")
                #expect(arguments(text) == arguments(english), "Format arguments changed: \(key)")
            }
        }
    }
}
