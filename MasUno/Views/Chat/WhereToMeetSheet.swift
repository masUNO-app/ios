import SwiftUI

/// Figma: "Edit meet-up" (341:2507) — the host's "Where to meet", pinned in the chat.
/// No spot photo (dropped in D1).
struct WhereToMeetSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var event: SportsEvent

    @State private var spot: String
    @State private var showsError = false
    private static let limit = 80

    init(event: SportsEvent) {
        self.event = event
        _spot = State(initialValue: event.meetUpSpot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where to meet")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Pinned at the top of the chat so nobody has to ask.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            FieldBox("Meet-up spot", error: showsError ? TextFilter.message : nil) {
                TextField("e.g. By the palms, near the tennis courts", text: $spot)
                    .onChange(of: spot) { if spot.count > Self.limit { spot = String(spot.prefix(Self.limit)) } }
            }

            Text("To change the date, time or location, edit the game from Me › Hosting.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            Button("Save") {
                guard TextFilter.isFriendly(spot) else { showsError = true; return }
                store.updateMeetUpSpot(event.id, to: spot.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
        }
        .padding(Theme.gutter)
        .padding(.top, 8)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}
