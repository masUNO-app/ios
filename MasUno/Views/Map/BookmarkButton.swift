import SwiftUI

/// Save / unsave a game (E17): a small glass circle on the popup's sport header. The icon fills
/// and turns green when saved. (Game details has the same action in its ••• menu.)
struct BookmarkButton: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    var event: Game

    var body: some View {
        let isSaved = store.isSaved(event.id)

        Button {
            if store.isGuest {
                appViewModel.requireAccount(.save)
                return
            }
            withAnimation(.snappy) { store.toggleSaved(event.id) }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSaved ? Theme.accent : Theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark")
        .sensoryFeedback(.selection, trigger: isSaved)
    }
}
