import SwiftUI

/// Figma: "Registered events" ("Your plans").
struct RegisteredEventsView: View {
    @Environment(EventStore.self) private var store
    private let viewModel = RegisteredEventsViewModel()

    var body: some View {
        let upcoming = viewModel.upcoming(in: store)
        let past = viewModel.past(in: store)

        PlansScaffold(
            title: "Your plans",
            subtitle: "Good times nearby. Your people, all here.",
            countLabel: viewModel.countLabel(in: store)
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
                        viewModel.leave(event.id, in: store)
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
