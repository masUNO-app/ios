import Foundation
import Observation

/// Root presentation state: navigation path and the game form sheet.
@Observable
final class AppViewModel {
    var path: [Route] = []
    var isAddingEvent = false
    var editingEventID: SportsEvent.ID?

    func editingEvent(in store: EventStore) -> SportsEvent? {
        editingEventID.flatMap { store.event($0) }
    }

    func startAdding(editing id: SportsEvent.ID? = nil) {
        editingEventID = id
        isAddingEvent = true
    }

    func dismissAdding() {
        isAddingEvent = false
        editingEventID = nil
    }

    #if DEBUG
    /// Jump straight to a screen for design review, e.g. launch with `-screen hosted`.
    /// Options: registered, hosted, add, form-error, edit, picker, gallery, detail-*, popup (handled in `EventMapViewModel`).
    func openDebugScreen(in store: EventStore) {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "registered": path = [.registered]
        case "hosted": path = [.hosted]
        case "add": startAdding()
        case "form-error", "picker": startAdding()
        case "edit": startAdding(editing: store.hostedEvents.first?.id)
        case "gallery": path = [.gallery]
        case let screen? where screen.hasPrefix("detail-"):
            if let id = Self.debugDetailID(screen, in: store) { path = [.game(id)] }
        default: break
        }
    }

    /// `-screen detail-open|in|full|hosting|ended|cancelled` (add `-raceJoin YES` to `detail-open`).
    private static func debugDetailID(_ screen: String, in store: EventStore) -> SportsEvent.ID? {
        let title = switch screen {
        case "detail-in": "Sunday soccer"
        case "detail-full": "Friday night 5v5"
        case "detail-hosting": "Volleyball night"
        case "detail-ended": "Morning shootaround"
        case "detail-cancelled": "Beach volleyball"
        default: "After-work hoops"
        }
        return store.events.first { $0.title == title }?.id
    }
    #endif
}
