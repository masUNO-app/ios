import Foundation
import Observation

/// Root presentation state: navigation path and the Add/Edit event sheet.
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
    /// Options: registered, hosted, add, popup (handled in `EventMapViewModel`).
    func openDebugScreen() {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "registered": path = [.registered]
        case "hosted": path = [.hosted]
        case "add": startAdding()
        default: break
        }
    }
    #endif
}
