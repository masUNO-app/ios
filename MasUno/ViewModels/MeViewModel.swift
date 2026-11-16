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
    /// The Invites sheet, from "Invite friends" on the profile card.
    var showsInvites = false
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

    /// "Invite friends · 2 left" while there are codes to give; plain "Invite friends" otherwise.
    func inviteTitle(for invites: [Invite]) -> String {
        let left = invites.filter { !$0.isUsed }.count
        return left > 0 ? String(localized: "Invite friends · \(left) left") : String(localized: "Invite friends")
    }

    /// "Group chat · 2 new", or just "Group chat".
    func chatTitle(unread: Int) -> String {
        unread > 0 ? String(localized: "Group chat · \(unread) new") : String(localized: "Group chat")
    }
}
