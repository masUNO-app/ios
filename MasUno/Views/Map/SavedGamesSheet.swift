import SwiftUI

/// Figma "Saved games", from the bookmark button on the map (E17). A full game you asked to
/// hear about shows "Spot alert is on" in place of "Count me in".
struct SavedGamesSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss
    /// Opens a game's detail from the list.
    var onOpen: (UUID) -> Void

    var body: some View {
        let games = store.savedGames()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(
                    title: Text("Saved games"),
                    subtitle: Text("Turn on a spot alert and we'll tell you when a full game opens up.")
                ) { dismiss() }

                if games.isEmpty {
                    EmptyCard(title: "Nothing saved yet", message: "Tap the bookmark on a game to keep it here.") {
                        Button("Find a game") { dismiss() }
                            .pill(.primary)
                    }
                }

                ForEach(games) { event in
                    Button {
                        open(event)
                    } label: {
                        card(event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 24)
            .animation(.snappy, value: games.map(\.id))
        }
        .task(id: games.map(\.id)) { await store.loadMissingAttendees(for: games.map(\.id)) }
        .sheetChrome(detents: [.medium, .large])
    }

    private func card(_ event: Game) -> some View {
        GameCard(
            event: event, lineup: store.lineup(for: event),
            status: status(for: event), time: EventFormat.cardTime(event)
        ) {
            Button("Remove") { store.toggleSaved(event.id) }
                .pill(.secondary, expands: false)
            action(for: event)
        }
    }

    private func status(for event: Game) -> String {
        if event.isCancelled { return event.cancelledLine }
        if event.isGoing { return event.isHostedByMe ? event.hostingLine : event.goingLine }
        guard event.isFull else { return event.discoverLine() }
        return store.hasSpotAlert(event.id)
            ? String(localized: "Full · we'll tell you if a spot opens")
            : String(localized: "Full")
    }

    @ViewBuilder
    private func action(for event: Game) -> some View {
        if event.isGoing || event.isCancelled {
            Button("View game") { open(event) }
                .pill(.primary)
        } else if event.isFull {
            let isOn = store.hasSpotAlert(event.id)
            Button(isOn ? "Spot alert is on" : "Alert me") { store.toggleSpotAlert(event.id) }
                .pill(.primary)
                .sensoryFeedback(.selection, trigger: isOn)
                .accessibilityHint(isOn ? "Turns the spot alert off" : "Tells you when a spot opens")
        } else {
            Button("Count me in") {
                dismiss()
                appViewModel.joinAndOpen(event.id, in: store)
            }
            .pill(.primary)
        }
    }

    private func open(_ event: Game) {
        dismiss()
        onOpen(event.id)
    }
}
