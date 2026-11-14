import SwiftUI

/// The games behind a group pin on the map, in the same rows as search results.
struct PinGroupSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var gameIDs: [UUID]
    var viewModel: EventMapViewModel
    /// Opens a game's detail from the list.
    var onOpen: (UUID) -> Void

    var body: some View {
        let games = gameIDs.compactMap { store.game($0) }

        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                title: Text("\(games.count) games here"),
                subtitle: Text("Close enough to share a pin. Zoom in to see each one.")
            ) { dismiss() }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(games) { event in
                        Button {
                            dismiss()
                            onOpen(event.id)
                        } label: {
                            GameListRow(event: event, line: viewModel.resultLine(for: event))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 22)
        .sheetChrome(detents: [.medium, .large])
    }
}

/// A game in a list over the map: sport tile, title, "Today, 7:35 PM · 0.4 km · room for 4".
struct GameListRow: View {
    var event: Game
    var line: String

    var body: some View {
        HStack(spacing: 14) {
            ActivityTile(sport: event.activity)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title)
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: line)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(.rect)
    }
}
