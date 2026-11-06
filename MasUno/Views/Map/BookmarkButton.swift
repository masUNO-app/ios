import SwiftUI

/// Save / unsave a game (E17) — the one bookmark control used everywhere (popup, Saved
/// list, game detail). Large glass circle; the icon fills and turns green when saved.
/// In a toolbar, which adds its own glass, it's just the icon.
struct BookmarkButton: View {
    @Environment(GameStore.self) private var store
    var event: Game
    var inToolbar = false

    var body: some View {
        let isSaved = store.isSaved(event.id)
        let button = Button {
            withAnimation(.snappy) { store.toggleSaved(event.id) }
        } label: {
            Label(
                isSaved ? "Remove bookmark" : "Bookmark",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            )
            .foregroundStyle(isSaved ? Theme.accent : Theme.ink)
            .contentTransition(.symbolEffect(.replace))
        }
        .labelStyle(.iconOnly)
        .sensoryFeedback(.selection, trigger: isSaved)

        if inToolbar {
            button
        } else {
            button
                .font(.title3.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    }
}
