import Foundation

/// Navigation destinations pushed on the root `NavigationStack`.
enum Route: Hashable {
    case game(UUID)
    case chat(UUID)
    case settings
    case blockedPeople
    case me(MeViewModel.Tab = .going, editsProfile: Bool = false)
    #if DEBUG
    case gallery
    #endif
}
