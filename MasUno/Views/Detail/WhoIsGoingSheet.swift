import SwiftUI

/// Figma: "Who's going" (341:2309). Initials, "Alex R.", Host badge, "(you)", and a flag
/// per row → Report / Block (SPEC §7.6.6). Blocked people vanish from the list immediately.
struct WhoIsGoingSheet: View {
    @Environment(GameStore.self) private var store
    var eventID: UUID

    @State private var reportTarget: ReportSubject?
    @State private var blockTarget: PersonSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.game(eventID) != nil {
                    let people = store.attendees(of: eventID)
                    VStack(alignment: .leading, spacing: 10) {
                        if people.isEmpty, store.isOffline {
                            RetryCard(message: "Couldn't load who's going.") { await store.loadAttendees(eventID) }
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(people.enumerated()), id: \.element.id) { index, attendee in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 64) }
                                row(attendee)
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
            .task { await store.loadAttendees(eventID) }
            .navigationTitle("Who's going")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .blockConfirmation(person: $blockTarget)
    }

    private func row(_ attendee: Attendee) -> some View {
        let person = attendee.person
        let isMe = person.id == store.profile?.id

        return HStack(spacing: 12) {
            Avatar(name: person.displayName, size: 36)
            Text(isMe ? "\(store.profile?.fullName ?? person.displayName) (you)" : person.displayName)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if attendee.role == .host {
                StatusChip(String(localized: "Host"))
            }
            if !isMe {
                Menu("Report or block \(person.displayName)", systemImage: "flag") {
                    Button("Report", systemImage: "exclamationmark.bubble") { reportTarget = .person(person) }
                    Button("Block", systemImage: "hand.raised", role: .destructive) { blockTarget = person }
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
    func blockConfirmation(person: Binding<PersonSummary?>, onBlocked: (() -> Void)? = nil) -> some View {
        modifier(BlockConfirmation(person: person, onBlocked: onBlocked))
    }
}

private struct BlockConfirmation: ViewModifier {
    @Environment(GameStore.self) private var store
    @Binding var person: PersonSummary?
    var onBlocked: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            Text("Block \(person?.displayName ?? "")?"),
            isPresented: Binding(get: { person != nil }, set: { if !$0 { person = nil } }),
            presenting: person
        ) { blocked in
            Button("Block", role: .destructive) {
                Task { await store.block(blocked) }
                onBlocked?()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's games or names, and neither of you can join the other's games.")
        }
    }
}
