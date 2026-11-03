import SwiftUI

/// Save / unsave a game (E17). Glass circle on cards; plain icon in a toolbar, which adds its own glass.
struct BookmarkButton: View {
    @Environment(EventStore.self) private var store
    var event: SportsEvent
    var inToolbar = false

    var body: some View {
        let button = Button(
            event.isBookmarked ? "Remove bookmark" : "Bookmark",
            systemImage: event.isBookmarked ? "bookmark.fill" : "bookmark"
        ) {
            withAnimation(.snappy) { store.toggleBookmark(event.id) }
        }
        .labelStyle(.iconOnly)
        .tint(Theme.ink)
        .contentTransition(.symbolEffect(.replace))

        if inToolbar {
            button
        } else {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
    }
}
