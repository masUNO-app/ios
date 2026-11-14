import MapKit
import Observation
import SwiftUI
import UIKit

/// Game details (SPEC §7.6.4, §7.7.4): which state you're in, the copy that goes with it, and
/// the join/leave/cancel intents.
@Observable
final class EventDetailViewModel {
    let eventID: UUID
    /// Game waiting on the Leave confirmation.
    var leaving: Game?
    /// Game waiting on the Cancel confirmation.
    var cancelling: Game?
    var showsWhoIsGoing = false
    var showsInvite = false
    var reportTarget: ReportSubject?
    var choosesMapsApp = false
    var addsToCalendar = false

    init(eventID: UUID) {
        self.eventID = eventID
    }

    // MARK: Presentation

    /// The bold line under the host: "Room for 4 more", "You're in!", "Game's full · 6 of 6"…
    func headline(for event: Game) -> String {
        switch event.status() {
        case .open: event.roomLine
        case .going: String(localized: "You're in!")
        case .full: event.fullLine
        case .hosting: String(localized: "Your game is live!")
        case .ended: String(localized: "This game has ended")
        case .cancelled:
            event.isHostedByMe
                ? String(localized: "You cancelled this game")
                : String(localized: "\(event.host.firstName) cancelled this game")
        }
    }

    /// "You're in!" and "Your game is live!" are the green ones.
    func isCelebrating(_ event: Game) -> Bool {
        [.going, .hosting].contains(event.status())
    }

    /// The sentence under the headline, for the states that have one.
    func detail(for event: Game, chatEnabled: Bool) -> String? {
        switch event.status() {
        case .going:
            chatEnabled
                ? String(localized: "\(event.host.firstName) knows you're coming. Say hi in the group chat, or just show up.")
                // Read-only group chat (SPEC N14).
                : String(localized: "\(event.host.firstName) knows you're coming. Check where to meet and who's going.")
        case .hosting:
            event.isFull
                ? String(localized: "Every spot is taken. See you on the court.")
                : String(localized: "It's on the map now with \(event.roomPhrase).")
        default: nil
        }
    }

    /// "Alex says" over the host's note; "You said" on your own game.
    func noteLabel(for event: Game) -> String {
        event.isHostedByMe ? String(localized: "You said") : String(localized: "\(event.host.firstName) says")
    }

    // MARK: Intents

    /// Shows "You're in" right away; `GameStore` rolls back if the server says the game filled.
    func join(in store: GameStore) {
        Task { await store.join(eventID) }
    }

    /// "Join me for After-work hoops — Today · 7:35 PM at Estadio Borregos. Room for 4 more on masUNO:"
    /// With an unused invite code of yours, it adds "Use my invite code ABCD-EFGH to skip the waitlist."
    /// so a friend still waiting can get in.
    static func inviteMessage(for event: Game, invites: [Invite] = []) -> String {
        let message = String(localized: "Join me for \(event.title) — \(EventFormat.dayAndTime(event.startsAt)) at \(event.place.name). \(event.roomLine) on masUNO:")
        guard let code = invites.first(where: { !$0.isUsed }) else { return message }
        return message + " " + String(localized: "Use my invite code \(code.displayCode) to skip the waitlist.")
    }

    /// Walking directions. Offers Google Maps too when it's installed (E19).
    func openInMaps(_ event: Game) {
        if Self.hasGoogleMaps {
            choosesMapsApp = true
        } else {
            openInAppleMaps(event)
        }
    }

    static var hasGoogleMaps: Bool {
        URL(string: "comgooglemaps://").map(UIApplication.shared.canOpenURL) ?? false
    }

    func openInGoogleMaps(_ event: Game) {
        let destination = "\(event.place.latitude),\(event.place.longitude)"
        guard let url = URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=walking") else { return }
        UIApplication.shared.open(url)
    }

    func openInAppleMaps(_ event: Game) {
        let location = CLLocation(latitude: event.place.latitude, longitude: event.place.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = event.place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
