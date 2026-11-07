import MapKit
import Observation
import SwiftUI
import UIKit

/// Game detail (SPEC §7.6.4): which 0.5 state you're in, and the join/leave/cancel intents.
@Observable
final class EventDetailViewModel {
    let eventID: UUID
    var confirmsLeave = false
    var confirmsCancel = false
    var showsWhoIsGoing = false
    var reportTarget: ReportSubject?
    var choosesMapsApp = false
    var addsToCalendar = false

    init(eventID: UUID) {
        self.eventID = eventID
    }

    // MARK: Presentation

    func chipText(for event: Game) -> String {
        switch event.status() {
        case .open: event.openLine
        case .going: String(localized: "You're in · \(event.statusLine)")
        case .full: String(localized: "Full")
        case .hosting: String(localized: "You're hosting · \(event.goingCount) going")
        case .ended: String(localized: "This game has ended")
        case .cancelled: String(localized: "\(event.host.displayName) cancelled this game")
        }
    }

    func chipIcon(for event: Game) -> String? {
        event.status() == .going ? "checkmark.circle.fill" : nil
    }

    /// "Alex R. (host), Ricardo T., you" — without anyone you blocked.
    func goingNames(for event: Game, in store: GameStore) -> String {
        store.attendees(of: event.id).map { attendee in
            let isMe = attendee.id == store.profile?.id
            let isHost = attendee.role == .host
            if isMe { return isHost ? String(localized: "you (host)") : String(localized: "you") }
            let display = attendee.person.displayName
            return isHost ? String(localized: "\(display) (host)") : display
        }
        .joined(separator: ", ")
    }

    // MARK: Intents

    /// Shows "You're in" right away; `GameStore` rolls back if the server says the game filled.
    func join(in store: GameStore) {
        Task { await store.join(eventID) }
    }

    func leave(in store: GameStore) {
        Task { await store.leave(eventID) }
    }

    func cancel(in store: GameStore) {
        Task { await store.cancelGame(eventID) }
    }

    /// "Join me for After-work hoops — Today · 7:35 PM at Estadio Borregos. 4 spots left on masUNO:"
    func inviteMessage(for event: Game) -> String {
        String(localized: "Join me for \(event.title) — \(EventFormat.dayAndTime(event.startsAt)) at \(event.place.name). \(event.spotsLine) on masUNO:")
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
