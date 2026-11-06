import EventKit
import EventKitUI
import SwiftUI

/// System "New Event" editor, prefilled with the game (E19). It runs outside the app,
/// so there's no calendar permission prompt. Host edits later don't update the entry.
struct CalendarEditor: UIViewControllerRepresentable {
    var event: Game
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let entry = EKEvent(eventStore: store)
        entry.title = event.title
        entry.startDate = event.startsAt
        entry.endDate = event.endsAt
        entry.location = "\(event.place.name), \(event.place.address)"
        entry.url = URL(string: "masuno://game/\(event.id.uuidString)")
        entry.notes = [
            event.meetPoint.map { String(localized: "Meet-up spot: \($0)") },
            event.notes,
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = entry
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator { dismiss() }
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
