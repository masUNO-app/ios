import Foundation

/// Sports you can post. Non-sport categories are out of scope during the program.
enum Sport: String, CaseIterable, Identifiable, Hashable {
    case basketball, tennis, soccer, volleyball

    var id: Self { self }

    var name: String {
        switch self {
        case .basketball: String(localized: "Basketball")
        case .tennis: String(localized: "Tennis")
        case .soccer: String(localized: "Soccer")
        case .volleyball: String(localized: "Volleyball")
        }
    }

    var emoji: String {
        switch self {
        case .basketball: "🏀"
        case .tennis: "🎾"
        case .soccer: "⚽️"
        case .volleyball: "🏐"
        }
    }

    static let postable: [Sport] = allCases
}
