import SwiftUI

/// The games behind a group pin on the map, in the same rows as search results. Also every game
/// on the map, for VoiceOver's "List plans".
struct PinGroupSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var gameIDs: [UUID]
    var viewModel: EventMapViewModel
    /// Nil for a group pin's "3 games here".
    var title: Text? = nil
    var subtitle: Text? = Text("Close enough to share a pin. Zoom in to see each one.")
    /// Opens a game's detail from the list.
    var onOpen: (UUID) -> Void

    var body: some View {
        let games = gameIDs.compactMap { store.game($0) }

        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: title ?? Text("\(games.count) plans here"), subtitle: subtitle) { dismiss() }

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
        .sheetChrome(detents: [.oneCard, .large])
    }
}

/// A game in a list over the map: sport tile, title, "Today, 7:35 PM · 0.4 km · room for 4".
struct GameListRow: View {
    var event: Game
    var line: String
    @Environment(\.dynamicTypeSize) private var typeSize

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
            // One line each, until the text is too big to fit anything on one line (A11Y-06).
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            RowAccessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 68)
        .contentShape(.rect)
    }
}
