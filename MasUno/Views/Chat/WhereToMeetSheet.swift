import SwiftUI

/// Figma: "Edit meet-up" (341:2507) — the host's "Where to meet", pinned in the chat.
/// No spot photo (dropped in D1).
struct WhereToMeetSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var event: Game

    @State private var spot: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var isFocused: Bool
    private static let limit = GameDraft.meetPointLimit

    init(event: Game) {
        self.event = event
        _spot = State(initialValue: event.meetPoint ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where to meet")
                    .font(.rounded(.title2, .bold))
                    .foregroundStyle(Theme.ink)
                Text("Pinned at the top of the chat so nobody has to ask.")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.muted)
            }

            FieldBox("Meet-up spot", error: errorMessage, isFocused: isFocused) {
                TextField("e.g. By the north court bleachers", text: $spot)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onChange(of: spot) { if spot.count > Self.limit { spot = String(spot.prefix(Self.limit)) } }
            }

            Text("To change the date, time or location, edit the game from Me › Hosting.")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.muted)

            Button("Save") {
                guard TextFilter.isFriendly(spot) else {
                    errorMessage = TextFilter.message
                    return
                }
                Task { await save() }
            }
            .disabled(isSaving)
            .pill(.primary)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetChrome(detents: [.height(330)])
        .onAppear { isFocused = true }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = spot.trimmingCharacters(in: .whitespaces)
        do {
            try await store.updateMeetPoint(event.id, to: trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = (error as? DomainError ?? .offline).message
        }
    }
}
