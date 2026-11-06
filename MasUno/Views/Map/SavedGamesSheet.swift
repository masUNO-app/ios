import SwiftUI

/// Saved games, from the bookmark button on the map (E17).
struct SavedGamesSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Opens a game's detail from the list.
    var onOpen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.savedGames().isEmpty {
                        ContentUnavailableView(
                            "No saved games",
                            systemImage: "bookmark",
                            description: Text("Tap the bookmark on a game to keep it here.")
                        )
                        .padding(.top, 48)
                    }
                    ForEach(store.savedGames()) { event in
                        Button {
                            dismiss()
                            onOpen(event.id)
                        } label: {
                            GameCard(event: event) {
                                BookmarkButton(event: event)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}
