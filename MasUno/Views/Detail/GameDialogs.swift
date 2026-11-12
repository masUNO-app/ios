import SwiftUI

extension View {
    /// Figma "Leave game": "Leave After-work hoops?" → **Leave game** / **Stay in**.
    func leaveGameDialog(_ game: Binding<Game?>) -> some View {
        modifier(LeaveGameDialog(game: game))
    }

    /// Figma "Delete game", as a soft cancel (SPEC R7-6): "Cancel Sunday pickup soccer?" →
    /// **Cancel game** / **Keep game**. `onCancelled` runs once the host confirms.
    func cancelGameDialog(_ game: Binding<Game?>, onCancelled: @escaping () -> Void = {}) -> some View {
        modifier(CancelGameDialog(game: game, onCancelled: onCancelled))
    }

    /// Figma "Block": "Block Ricardo?" (SPEC §7.6.6). Blocking hides them right away.
    func blockDialog(_ person: Binding<PersonSummary?>, onBlocked: @escaping () -> Void = {}) -> some View {
        modifier(BlockDialog(person: person, onBlocked: onBlocked))
    }
}

private struct LeaveGameDialog: ViewModifier {
    @Environment(GameStore.self) private var store
    @Binding var game: Game?

    func body(content: Content) -> some View {
        content.dialog(item: $game) { game in
            DialogCard(
                systemImage: "rectangle.portrait.and.arrow.right", tone: .destructive,
                title: Text("Leave \(game.title)?"),
                message: Text("Your spot opens up for someone else and \(game.host.firstName) gets a heads-up. You'll leave the group chat too."),
                confirm: .init("Leave game") { Task { await store.leave(game.id) } },
                cancel: .init("Stay in")
            )
        }
    }
}

private struct CancelGameDialog: ViewModifier {
    @Environment(GameStore.self) private var store
    @Binding var game: Game?
    var onCancelled: () -> Void

    func body(content: Content) -> some View {
        content.dialog(item: $game) { game in
            DialogCard(
                systemImage: "trash", tone: .destructive,
                title: Text("Cancel \(game.title)?"),
                message: Text(message(for: game)),
                footnote: Text("This can't be undone."),
                confirm: .init("Cancel game") {
                    Task { await store.cancelGame(game.id) }
                    onCancelled()
                },
                cancel: .init("Keep game")
            )
        }
    }

    private func message(for game: Game) -> String {
        switch game.joinedCount {
        case 0: String(localized: "Nobody has joined yet. It comes off the map and the group chat closes.")
        case 1: String(localized: "We'll let the 1 person who joined know it's cancelled and close the group chat.")
        default: String(localized: "We'll let the \(game.joinedCount) people who joined know it's cancelled and close the group chat.")
        }
    }
}

private struct BlockDialog: ViewModifier {
    @Environment(GameStore.self) private var store
    @Binding var person: PersonSummary?
    var onBlocked: () -> Void

    func body(content: Content) -> some View {
        content.dialog(item: $person) { person in
            DialogCard(
                systemImage: "nosign", tone: .destructive,
                title: Text("Block \(person.firstName)?"),
                message: Text("You won't see each other's games or messages, and neither of you can join the other's games. We won't tell \(person.firstName)."),
                footnote: Text("You can unblock anytime in Settings."),
                confirm: .init("Block") {
                    Task { await store.block(person) }
                    onBlocked()
                },
                cancel: .init("Cancel")
            )
        }
    }
}
