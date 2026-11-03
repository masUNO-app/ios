import SwiftUI

/// Save / unsave a game (E17). On cards: a large glass circle that turns solid green when
/// saved. In a toolbar (which adds its own glass): an icon that turns green when saved.
struct BookmarkButton: View {
    @Environment(EventStore.self) private var store
    var event: SportsEvent
    var inToolbar = false

    var body: some View {
        let isSaved = event.isBookmarked
        let button = Button(
            isSaved ? "Remove bookmark" : "Bookmark",
            systemImage: isSaved ? "bookmark.fill" : "bookmark"
        ) {
            withAnimation(.snappy) { store.toggleBookmark(event.id) }
        }
        .labelStyle(.iconOnly)
        .contentTransition(.symbolEffect(.replace))
        .sensoryFeedback(.selection, trigger: isSaved)

        if inToolbar {
            button.tint(isSaved ? Theme.accent : Theme.ink)
        } else if isSaved {
            button
                .font(.title3.weight(.semibold))
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Theme.accent)
        } else {
            button
                .font(.title3.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Theme.ink)
        }
    }
}
