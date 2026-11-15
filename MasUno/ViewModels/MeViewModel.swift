import Observation
import SwiftUI

/// Me (SPEC §7.6.5): your profile card plus Going and Hosting lists.
/// Earlier games (last 14 days) and Edit profile and sports are E21.
@Observable
final class MeViewModel {
    enum Tab: Hashable {
        case going, hosting
    }

    var tab: Tab
    /// Game waiting on the Leave confirmation.
    var leaving: Game?
    var editsProfile = false
    /// "Report" on an earlier game.
    var reportTarget: ReportSubject?
    /// Earlier games are collapsed until you open them.
    var showsEarlier = false

    init(tab: Tab = .going) {
        self.tab = tab
    }

    func classLine(for profile: Profile) -> String {
        String(localized: "Class of \(String(profile.gradYear)) · \(profile.university.name)")
    }

    /// "Group chat · 2 new", or just "Group chat".
    func chatTitle(unread: Int) -> String {
        unread > 0 ? String(localized: "Group chat · \(unread) new") : String(localized: "Group chat")
    }
}
