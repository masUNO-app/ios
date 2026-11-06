import SwiftUI

/// Figma: "Who's going" (341:2309). Initials, "Alex R.", Host badge, "(you)", and a flag
/// per row → Report / Block (SPEC §7.6.6). Blocked people vanish from the list immediately.
struct WhoIsGoingSheet: View {
    @Environment(EventStore.self) private var store
    var eventID: SportsEvent.ID

    @State private var reportTarget: LegacyReportTarget?
    @State private var blockTarget: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let event = store.event(eventID) {
                    let people = store.visibleAttendees(of: event)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(people.enumerated()), id: \.element) { index, name in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 64) }
                                row(name, in: event)
                            }
                        }
                        .cardSurface()

                        Text("Tap the flag next to someone to report or block them. Only the masUNO team sees reports.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .animation(.default, value: people)
                }
            }
            .background(Theme.background)
            .navigationTitle("Who's going")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .blockConfirmation(person: $blockTarget)
    }

    private func row(_ name: String, in event: SportsEvent) -> some View {
        HStack(spacing: 12) {
            Avatar(name: name, size: 36)
            Text(name == Person.you ? "\(store.profile.fullName) (you)" : Person.display(name))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if name == event.host {
                StatusChip(String(localized: "Host"))
            }
            if name != Person.you {
                Menu("Report or block \(Person.display(name))", systemImage: "flag") {
                    Button("Report", systemImage: "exclamationmark.bubble") { reportTarget = .person(name) }
                    Button("Block", systemImage: "hand.raised", role: .destructive) { blockTarget = name }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(Theme.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}

extension View {
    /// "Block Alex R.?" confirmation (SPEC §7.6.6). Blocking hides them right away.
    func blockConfirmation(person: Binding<String?>, onBlocked: (() -> Void)? = nil) -> some View {
        modifier(BlockConfirmation(person: person, onBlocked: onBlocked))
    }
}

private struct BlockConfirmation: ViewModifier {
    @Environment(EventStore.self) private var store
    @Binding var person: String?
    var onBlocked: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            Text("Block \(Person.display(person ?? ""))?"),
            isPresented: Binding(get: { person != nil }, set: { if !$0 { person = nil } }),
            presenting: person
        ) { name in
            Button("Block", role: .destructive) {
                withAnimation { store.block(name) }
                onBlocked?()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's games or names, and neither of you can join the other's games.")
        }
    }
}
