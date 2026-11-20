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
            Self.toggle(event, store: store, appViewModel: appViewModel)
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSaved ? Theme.accent : Theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .appGlass(in: .circle, interactive: true)
                // A 44 pt target around the 36 pt circle; the padding below takes the room back,
                // so nothing moves (A11Y-19).
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(-4)
        .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark")
        .sensoryFeedback(.selection, trigger: isSaved)
    }

    /// For a guest it asks them to make an account, like every other account action.
    static func toggle(_ event: Game, store: GameStore, appViewModel: AppViewModel) {
        if store.isGuest {
            appViewModel.requireAccount(.save)
            return
        }
        withAnimation(.snappy) { store.toggleSaved(event.id) }
    }
}
