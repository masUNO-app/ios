import SwiftUI

/// Figma: "Popup" (341:2046) — the game card with a tail, opening from a pin on the map.
struct EventPopup: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    var event: Game
    var viewModel: EventMapViewModel

    var body: some View {
        VStack(spacing: 0) {
            GameCard(
                event: event, lineup: store.lineup(for: event),
                status: event.discoverLine(), time: EventFormat.cardTime(event), isFloating: true
            ) {
                BookmarkButton(event: event)
            } actions: {
                Button("Details") { appViewModel.path.append(.game(event.id)) }
                    .pill(.secondary, expands: false)
                primaryAction
                    .pill(.primary)
            }

            CalloutTail()
                .fill(Theme.card)
                .frame(width: 28, height: 13)
                .shadow(color: Theme.ink.opacity(0.12), radius: 3, y: 4)
                // Tucked under the card so the border doesn't show between them.
                .padding(.top, -1)
        }
        .task(id: event.id) { await store.loadAttendees(event.id) }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByMe {
            Button("Edit game") { appViewModel.presentGameForm(editing: event.id) }
        } else if event.isGoing {
            Button("View game") { appViewModel.path.append(.game(event.id)) }
        } else {
            Button("Count me in") { viewModel.join(event.id, in: store) }
        }
    }
}
