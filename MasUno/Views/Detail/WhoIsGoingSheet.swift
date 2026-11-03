import SwiftUI

/// Figma: "Who's going" (341:2309). Initials, "Alex R.", Host badge, "(you)".
struct WhoIsGoingSheet: View {
    @Environment(EventStore.self) private var store
    var eventID: SportsEvent.ID

    var body: some View {
        NavigationStack {
            ScrollView {
                if let event = store.event(eventID) {
                    VStack(spacing: 0) {
                        ForEach(Array(event.attendees.enumerated()), id: \.element) { index, name in
                            if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 64) }
                            row(name, in: event)
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .background(Theme.background)
            .navigationTitle("Who's going")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
