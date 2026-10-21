import Foundation

/// Navigation destinations pushed on the root `NavigationStack`.
enum Route: Hashable {
    case registered
    case hosted
    case chat(SportsEvent.ID)
}
