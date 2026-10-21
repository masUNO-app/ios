import SwiftUI

/// Figma: "Hosted events" ("You're the host").
///
/// NOTE: The Figma frame also has a "Join requests" section with Accept/Decline
/// buttons and a "N join requests waiting for your review" banner. Organizer
/// approval is post-MVP, so it's intentionally left out here — spots are
/// first come, first served (see `EventStore.rsvp`).
struct HostedEventsView: View {
    @Environment(EventStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    private let viewModel = HostedEventsViewModel()

    var body: some View {
        let upcoming = viewModel.upcoming(in: store)

        PlansScaffold(
            title: "You're the host",
            subtitle: "Bring your neighborhood together.",
            countLabel: viewModel.countLabel(in: store)
        ) {
            PlansSectionHeader(title: "Coming up · \(upcoming.count)", trailing: "People counts include you")
            if upcoming.isEmpty {
                ContentUnavailableView(
                    "Nothing hosted yet",
                    systemImage: "plus.circle",
                    description: Text("Post a game in under a minute with Add event.")
                )
            }
            ForEach(upcoming) { event in
                PlanEventCard(event: event, status: "You · Host", metaNoun: "people") {
                    Button {
                        appViewModel.startAdding(editing: event.id)
                    } label: {
                        Text("Edit event")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.ink)

                    // Join requests (Accept/Decline) go here once organizer approval ships.

                    GroupChatPreview(event: event)
                }
            }
        }
    }
}
