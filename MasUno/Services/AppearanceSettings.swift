import Observation
import UIKit

/// Light or dark: the phone's setting, or one picked in Settings › Appearance. Persisted like the
/// language choice; tests and screenshots force it with `-appearance dark`.
@Observable
final class AppearanceSettings {
    enum Preference: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }

        var style: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    }

    static let shared = AppearanceSettings()
    static let preferenceKey = "appearance"

    var preference: Preference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.preferenceKey)
            apply()
        }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = Preference(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
    }

    /// Sets the choice on the windows rather than with `preferredColorScheme`, so sheets, dialogs,
    /// the map's annotations and UIKit's bars all follow it, and System hands it back to the phone.
    func apply(to scenes: Set<UIScene> = UIApplication.shared.connectedScenes) {
        for case let scene as UIWindowScene in scenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != preference.style {
                window.overrideUserInterfaceStyle = preference.style
            }
        }
    }
}
