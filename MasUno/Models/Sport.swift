import Foundation

enum Sport: String, CaseIterable, Identifiable, Hashable {
    case basketball, tennis, soccer, volleyball
    // Non-sport categories only appear in the plans mock data from Figma.
    // MVP posting is limited to `Sport.postable`.
    case music, social, games

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .basketball: "🏀"
        case .tennis: "🎾"
        case .soccer: "⚽️"
        case .volleyball: "🏐"
        case .music: "🎵"
        case .social: "☕️"
        case .games: "🎲"
        }
    }

    /// SF Symbol for the icon tile on plan cards (non-sport events).
    var symbol: String? {
        switch self {
        case .music: "music.note"
        case .social: "cup.and.saucer"
        case .games: "dice"
        default: nil
        }
    }

    var category: String {
        switch self {
        case .basketball, .tennis, .soccer, .volleyball: "Sports"
        case .music: "Music"
        case .social: "Social"
        case .games: "Games"
        }
    }

    static let postable: [Sport] = [.basketball, .tennis, .soccer, .volleyball]
}

enum SkillLevel: String, CaseIterable, Identifiable {
    case allLevels = "All levels"
    case casual = "Casual"
    case competitive = "Competitive"

    var id: Self { self }
}
