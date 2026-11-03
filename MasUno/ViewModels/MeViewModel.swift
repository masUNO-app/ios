import Observation
import SwiftUI

/// Me (SPEC §7.6.5): your profile card plus Going and Hosting lists.
/// Past games and Edit profile & interests come in 2.0 (E21).
@Observable
final class MeViewModel {
    enum Tab: Hashable {
        case going, hosting
    }

    var tab: Tab
    /// Game waiting on the Leave confirmation.
    var leaving: SportsEvent?

    init(tab: Tab = .going) {
        self.tab = tab
    }

    /// Upcoming games you joined, by start time. Cancelled ones stay (with a chip) until
    /// they would have ended.
    func going(in store: EventStore) -> [SportsEvent] {
        store.goingEvents.filter { !$0.hasEnded }
    }

    func hosting(in store: EventStore) -> [SportsEvent] {
        store.hostedEvents.filter { !$0.hasEnded }
    }

    func classLine(for profile: Profile) -> String {
        String(localized: "Class of \(String(profile.classYear)) · \(profile.school)")
    }

    func leave(_ event: SportsEvent, in store: EventStore) {
        withAnimation { store.leave(event.id) }
    }
}
