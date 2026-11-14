import SwiftUI

/// Figma: "Who's going" (408:6285). Token, "Alex R." with a green HOST tag, class year, and
/// ••• → Report / Block on everyone but you (SPEC §7.6.6). Then one row for the open spots and
/// the safety note. Blocked people vanish from the list immediately.
struct WhoIsGoingSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var eventID: UUID

    @State private var reportTarget: ReportSubject?
    @State private var blockTarget: PersonSummary?

    var body: some View {
        ScrollView {
            if let event = store.game(eventID) {
                let people = store.attendees(of: eventID)

                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(
                        title: Text("Who's going"),
                        subtitle: Text("\(event.goingCount) going"),
                        isProminent: true
                    ) { dismiss() }

                    if people.isEmpty, store.isOffline {
                        RetryCard(message: "Couldn't load who's going.") { await store.loadAttendees(eventID) }
                    }

                    VStack(spacing: 0) {
                        ForEach(people) { attendee in
                            row(attendee)
                            Theme.separator.frame(height: 1)
                        }
                        if !event.isFull, !event.isCancelled, !event.hasEnded() {
                            HStack(spacing: 12) {
                                OpenSpotToken(size: 36, fill: .clear)
                                Text(verbatim: event.roomLine)
                                    .font(.rounded(.callout, .bold))
                                    .foregroundStyle(Theme.ink)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 66)
                        }
                    }

                    SafetyNote(text: "Anything feel off? Tap ••• next to anyone to report or block them. Only the masUNO team sees reports.")
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .animation(.default, value: people)
            }
        }
        .task { await store.loadAttendees(eventID) }
        .sheetChrome(detents: [.fraction(0.82), .large], background: Theme.card)
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .blockDialog($blockTarget)
        #if DEBUG
        .onAppear {
            // `-screen block`: the Block confirmation, over the list.
            if UserDefaults.standard.string(forKey: "screen") == "block" {
                blockTarget = store.attendees(of: eventID).last?.person
            }
        }
        #endif
    }

    private func row(_ attendee: Attendee) -> some View {
        let person = attendee.person
        let isMe = person.id == store.profile?.id

        return HStack(spacing: 12) {
            PersonAvatar(person: person, size: 42, ring: 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: isMe ? String(localized: "\(store.profile?.fullName ?? person.displayName) (you)") : person.displayName)
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                    if attendee.role == .host {
                        Text("Host")
                            .textCase(.uppercase)
                            .font(.rounded(.caption2, .heavy))
                            .tracking(0.4)
                            .foregroundStyle(Theme.accent)
                    }
                }
                // Class year only: interests are private (SPEC §8.8, R7-4).
                Text("Class of \(String(person.gradYear))")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isMe {
                Menu("Report or block \(person.displayName)", systemImage: "ellipsis") {
                    Button("Report \(person.firstName)", systemImage: "exclamationmark.bubble") { reportTarget = .person(person) }
                    Button("Block \(person.firstName)", systemImage: "nosign", role: .destructive) { blockTarget = person }
                }
                .glassCircle()
            }
        }
        .frame(minHeight: 66)
        .accessibilityElement(children: .combine)
    }
}
