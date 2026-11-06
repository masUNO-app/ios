import Observation
import SwiftUI

/// Me (SPEC §7.6.5): your profile card plus Going and Hosting lists.
/// Past games (last 14 days) and Edit profile & interests are E21.
@Observable
final class MeViewModel {
    enum Tab: Hashable {
        case going, hosting
    }

    var tab: Tab
    /// Game waiting on the Leave confirmation.
    var leaving: Game?
    var editsProfile = false
    /// Past is collapsed until you open it.
    var showsPast = false

    init(tab: Tab = .going) {
        self.tab = tab
    }

    func classLine(for profile: Profile) -> String {
        String(localized: "Class of \(String(profile.gradYear)) · \(profile.universityName)")
    }

    func leave(_ game: Game, in store: GameStore) {
        Task { await store.leave(game.id) }
    }
}
