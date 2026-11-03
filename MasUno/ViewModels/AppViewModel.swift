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
    /// Options: registered, hosted, add, form-error, edit, gallery, popup (handled in `EventMapViewModel`).
    func openDebugScreen(in store: EventStore) {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "registered": path = [.registered]
        case "hosted": path = [.hosted]
        case "add": startAdding()
        case "form-error": startAdding()
        case "edit": startAdding(editing: store.hostedEvents.first?.id)
        case "gallery": path = [.gallery]
        default: break
        }
    }
    #endif
}
