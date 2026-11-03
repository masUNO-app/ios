import Foundation

/// Navigation destinations pushed on the root `NavigationStack`.
enum Route: Hashable {
    case game(SportsEvent.ID)
    case chat(SportsEvent.ID)
    case settings
    case blockedPeople
    case me(MeViewModel.Tab = .going, editsProfile: Bool = false)
    #if DEBUG
    case gallery
    #endif
}
