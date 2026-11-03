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
                    description: Text("Join a game on the map and it shows up here.")
                )
            }
            ForEach(upcoming) { event in
                GameCard(event: event) {
                    Button("Leave") { viewModel.leave(event.id, in: store) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accentSoft)
                        .foregroundStyle(Theme.ink)
                } footer: {
                    GroupChatPreview(event: event)
                }
            }

            if !past.isEmpty {
                PlansSectionHeader(title: "Past · \(past.count)", trailing: "Keep the connection")
                ForEach(past) { event in
                    GameCard(event: event, status: String(localized: "Game ended")) {
                        GroupChatPreview(event: event)
                    }
                }
            }
        }
    }
}
