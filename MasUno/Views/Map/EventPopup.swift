import SwiftUI

/// Figma: "Popup" (341:2046) — the game card with a tail, opening from a pin on the map.
struct EventPopup: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    var event: Game
    var viewModel: EventMapViewModel
    /// Set when Leave is tapped, so the confirmation can name the game.
    @State private var leaving: Game?
    /// VoiceOver moves from the pin to the card's summary as the popup opens (A11Y-02).
    @AccessibilityFocusState private var isSummaryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            GameCard(
                event: event, lineup: store.lineup(for: event),
                status: event.discoverLine(), time: EventFormat.cardTime(event), isFloating: true,
                shortcuts: shortcuts, summaryFocus: $isSummaryFocused
            ) {
                // For a guest it asks them to make an account, like every other account action.
                BookmarkButton(event: event)
            } actions: {
                // Once you're in, Details and View game open the same screen.
                if event.isGoing, !event.isHostedByMe {
                    Button("Leave") { leaving = event }
                        .pill(.secondary, expands: false)
                        .accessibilityLabel(String.app("Leave \(event.title)"))
                        .accessibilityInputLabels([Text("Leave")])
                } else {
                    Button("Details") { appViewModel.path.append(.game(event.id)) }
                        .pill(.secondary, expands: false)
                        .accessibilityLabel(String.app("Details, \(event.title)"))
                        .accessibilityInputLabels([Text("Details")])
                }
                primaryAction
                    .pill(.primary)
            }
            // Its own height, whatever MapKit offers: squeezed, the host line cut to "…".
            .fixedSize(horizontal: false, vertical: true)

            CalloutTail()
                .fill(Theme.card)
                .frame(width: 28, height: 13)
                .shadow(color: Theme.ink.opacity(0.12), radius: 3, y: 4)
                // Tucked under the card so the border doesn't show between them.
                .padding(.top, -1)
        }
        // Guest previews have no names to load.
        .task(id: event.id) {
            guard !event.hidesPeople else { return }
            await store.loadAttendees(event.id)
        }
        // The popup is its own annotation, drawn after the pin, so focus would stay on the pin.
        // Needs checking on a device with VoiceOver, on iOS 18 and 26+: that focus crosses
        // MapKit's annotation hosting. If it doesn't, announce instead from here, e.g.
        // `Announce.post("\(event.title) card. Swipe right for Count me in.")` (plan A11Y-02).
        .task(id: event.id) {
            // Read directly: annotation content doesn't inherit the map's environment.
            guard UIAccessibility.isVoiceOverRunning else { return }
            // After the grow animation (0.4 s).
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            isSummaryFocused = true
        }
        // Stops growing here, so the card still fits above its pin; Game details has the full
        // text at any size (A11Y-06). Arianna picks the cap. Before the dialog, which isn't capped.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .leaveGameDialog($leaving)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByMe {
            Button("Edit game") { appViewModel.presentGameForm(editing: event.id) }
        } else if event.isGoing {
            Button("View game") { appViewModel.path.append(.game(event.id)) }
                .accessibilityLabel(String.app("View game, \(event.title)"))
                .accessibilityInputLabels([Text("View game")])
        } else {
            Button("Count me in") { appViewModel.joinAndOpen(event.id, in: store) }
                .accessibilityLabel(String.app("Count me in, \(event.title)"))
                .accessibilityInputLabels([Text("Count me in")])
        }
    }

    /// VoiceOver actions on the card's summary, for the bookmark and Leave.
    private var shortcuts: [GameCardShortcut] {
        var shortcuts = [GameCardShortcut(name: store.isSaved(event.id) ? String.app("Remove bookmark") : String.app("Bookmark")) {
            BookmarkButton.toggle(event, store: store, appViewModel: appViewModel)
        }]
        if event.isGoing, !event.isHostedByMe {
            shortcuts.append(GameCardShortcut(name: String.app("Leave")) { leaving = event })
        }
        return shortcuts
    }
}
