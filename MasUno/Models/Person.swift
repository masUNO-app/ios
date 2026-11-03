import Foundation

enum Person {
    /// The signed-in user. There's no auth yet, so "You" is a fixed local identity.
    static let you = "You"

    /// How others appear in the app (SPEC §7.2): "Alex Rivera" → "Alex R.".
    /// Your own name only appears in full on your Me card.
    static func display(_ name: String) -> String {
        if name == you { return String(localized: "You") }
        let parts = name.split(separator: " ")
        guard parts.count > 1, let initial = parts.last?.first else { return name }
        return "\(parts[0]) \(initial)."
    }

    static func firstName(_ name: String) -> String {
        name == you ? String(localized: "You") : String(name.split(separator: " ").first ?? Substring(name))
    }
}
