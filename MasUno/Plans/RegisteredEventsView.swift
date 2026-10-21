import SwiftUI

/// Figma: "Registered events" ("Your plans").
struct RegisteredEventsView: View {
    @Environment(EventStore.self) private var store

    var body: some View {
        let events = store.registeredEvents
        let upcoming = events.filter { !$0.hasEnded }.sorted { $0.start < $1.start }
        let past = events.filter(\.hasEnded).sorted { $0.start > $1.start }

        PlansScaffold(
            title: "Your plans",
            subtitle: "Good times nearby. Your people, all here.",
            countLabel: "\(events.count) registered event\(events.count == 1 ? "" : "s")"
        ) {
            PlansSectionHeader(title: "Coming up · \(upcoming.count)", trailing: "Your next neighborhood hang")
            if upcoming.isEmpty {
                ContentUnavailableView(
                    "No plans yet",
                    systemImage: "sportscourt",
                    description: Text("RSVP to a game on the map and it shows up here.")
                )
            }
            ForEach(upcoming) { event in
                PlanEventCard(event: event, status: "Registered · You're going", statusIcon: "checkmark.circle") {
                    GroupChatPreview(event: event)
                    Button("Can't make it? Give up your spot", role: .destructive) {
                        withAnimation { store.leave(event.id) }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                }
            }

            if !past.isEmpty {
                PlansSectionHeader(title: "Past · \(past.count)", trailing: "Keep the connection")
                ForEach(past) { event in
                    PlanEventCard(event: event, status: "Registered · Event ended", statusIcon: "checkmark.circle") {
                        GroupChatPreview(event: event)
                    }
                }
            }
        }
    }
}
