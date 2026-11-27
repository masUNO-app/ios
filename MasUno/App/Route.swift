import Foundation

/// Navigation destinations pushed on the root `NavigationStack`.
enum Route: Hashable {
    case game(UUID)
    case chat(UUID)
    case settings
    case blockedPeople
    case guidelines
    case me(MeViewModel.Tab = .going, editsProfile: Bool = false)
    /// Props: your campus's top teammates this month (1.0).
    case leaderboard
    #if DEBUG
    case gallery
    #endif
}
