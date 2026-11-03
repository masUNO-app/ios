import SwiftUI

/// Saved games, from the bookmark button on the map (E17).
struct SavedGamesSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Opens a game's detail from the list.
    var onOpen: (SportsEvent.ID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.bookmarkedEvents.isEmpty {
                        ContentUnavailableView(
                            "No saved games",
                            systemImage: "bookmark",
                            description: Text("Tap the bookmark on a game to keep it here.")
                        )
                        .padding(.top, 48)
                    }
                    ForEach(store.bookmarkedEvents) { event in
                        Button {
                            dismiss()
                            onOpen(event.id)
                        } label: {
                            GameCard(event: event) {
                                Button(
                                    "Remove bookmark", systemImage: "bookmark.fill"
                                ) { withAnimation { store.toggleBookmark(event.id) } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .tint(Theme.ink)
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
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}
