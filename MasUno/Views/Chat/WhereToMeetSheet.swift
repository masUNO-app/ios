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
    @AccessibilityFocusState private var isErrorFocused: Bool
    private static let limit = GameDraft.meetPointLimit

    init(event: Game) {
        self.event = event
        _spot = State(initialValue: event.meetPoint ?? "")
    }

    var body: some View {
        // Scrolls only when the keyboard leaves less than the sheet's height (short windows).
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(
                    title: Text("Where to meet"),
                    subtitle: Text("Pinned at the top of the chat so nobody has to ask.")
                ) { dismiss() }

                FieldBox(
                    "Meet-up spot", text: $spot, prompt: Text("e.g. By the big tree outside the library"),
                    error: errorMessage, isFocused: isFocused
                ) { field in
                    field
                        .focused($isFocused)
                        .accessibilityFocused($isErrorFocused)
                        .submitLabel(.done)
                        .onChange(of: spot) { if spot.count > Self.limit { spot = String(spot.prefix(Self.limit)) } }
                }

                Text("To change the date, time or location, edit the plan from Me › Hosting.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)

                Button("Save") {
                    guard TextFilter.isFriendly(spot) else { return showError(TextFilter.message) }
                    Task { await save() }
                }
                .disabled(isSaving)
                .pill(.primary)
                .keyboardShortcut(.defaultAction) // Return on a hardware keyboard (A11Y-20).
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheetChrome(detents: [.height(330), .large])
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
            guard !OperationCancellation.isCancellation(error) else { return }
            showError((error as? DomainError ?? .offline).message)
        }
    }

    /// Under the field, and VoiceOver moves there and says it.
    private func showError(_ message: String) {
        errorMessage = message
        isErrorFocused = true
        Announce.post(message, priority: .high)
    }
}
