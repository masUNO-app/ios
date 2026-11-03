import Foundation

/// Navigation destinations pushed on the root `NavigationStack`.
enum Route: Hashable {
    case registered
    case hosted
    case game(SportsEvent.ID)
    case blockedPeople
    case chat(SportsEvent.ID)
    #if DEBUG
    case gallery
    #endif
}
