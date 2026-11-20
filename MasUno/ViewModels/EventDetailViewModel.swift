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
        case .going: String.app("You're in!")
        case .full: event.fullLine
        case .hosting: String.app("Your plan is live!")
        case .ended: String.app("This plan has wrapped")
        case .cancelled:
            event.isHostedByMe
                ? String.app("You cancelled this plan")
                : String.app("\(event.host.firstName) cancelled this plan")
        }
    }

    /// Said when "Count me in" goes through, since only the headline's color and text change.
    func joinAnnouncement(from old: GameStatus, to new: GameStatus, for event: Game) -> String? {
        old == .open && new == .going ? headline(for: event) : nil
    }

    /// "You're in!" and "Your plan is live!" are the green ones.
    func isCelebrating(_ event: Game) -> Bool {
        [.going, .hosting].contains(event.status())
    }

    /// The sentence under the headline, for the states that have one.
    func detail(for event: Game, chatEnabled: Bool) -> String? {
        switch event.status() {
        case .going:
            chatEnabled
                ? String.app("\(event.host.firstName) knows you're coming. Say hi in the group chat, or just show up.")
                // Read-only group chat (SPEC N14).
                : String.app("\(event.host.firstName) knows you're coming. Check where to meet and who's going.")
        case .hosting:
            event.isFull
                ? String.app("Every spot is taken. See you there.")
                : String.app("It's on the map now with \(event.roomPhrase).")
        default: nil
        }
    }

    /// "Alex says" over the host's note; "You said" on your own game.
    func noteLabel(for event: Game) -> String {
        event.isHostedByMe ? String.app("You said") : String.app("\(event.host.firstName) says")
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
        let message = String.app("Join me for \(event.title) — \(EventFormat.dayAndTime(event.startsAt)) at \(event.place.name). \(event.roomLine) on masUNO:")
        guard let code = invites.first(where: { !$0.isUsed }) else { return message }
        return message + " " + String.app("Use my invite code \(code.displayCode) to skip the waitlist.")
    }

    /// Walking directions. Offers Google Maps too when it's installed (E19).
    func openInMaps(_ event: Game) {
        if Self.hasGoogleMaps {
            choosesMapsApp = true
        } else {
            openInAppleMaps(event)
        }
    }

    /// SwiftUI has no `canOpenURL`, so this one still asks `UIApplication` (the scheme is in
    /// `LSApplicationQueriesSchemes`).
    static var hasGoogleMaps: Bool {
        URL(string: "comgooglemaps://").map(UIApplication.shared.canOpenURL) ?? false
    }

    /// Walking directions in Google Maps. The view opens it with its `openURL` action.
    static func googleMapsURL(for event: Game) -> URL? {
        let destination = "\(event.place.latitude),\(event.place.longitude)"
        return URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=walking")
    }

    func openInAppleMaps(_ event: Game) {
        let location = CLLocation(latitude: event.place.latitude, longitude: event.place.longitude)
        let item = LocationService.mapItem(location: location, name: event.place.name)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
