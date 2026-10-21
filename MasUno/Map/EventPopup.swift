import SwiftUI

/// Figma: "Basketball Game Pop-up" in "Sports event map · Popup".
struct EventPopup: View {
    @Environment(EventStore.self) private var store
    var event: SportsEvent
    @Binding var path: [Route]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(name: event.host, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Theme.ink)
                    Text(event.capacitySummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                    Text("Hosted by \(event.host) · \(event.skillLevel.rawValue)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
                Button {
                    store.toggleBookmark(event.id)
                } label: {
                    Image(systemName: event.isBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(Theme.orange)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(event.isBookmarked ? "Remove bookmark" : "Bookmark")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.youRed)
                Text("\(event.start.formatted(date: .numeric, time: .shortened)) · \(EventFormat.countdown(to: event.start)) until start")
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink)

            Text(event.venue.fullAddress)
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tan, in: .rect(cornerRadius: 8))

            if !event.guests.isEmpty {
                Text("Going: \(event.attendees.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Text(event.sport.category)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Theme.tan, in: .capsule)
                    .overlay(Capsule().stroke(Theme.tanStroke))

                primaryAction
                    .buttonStyle(OrangeCapsuleStyle(foreground: .white))
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.tanStroke.opacity(0.6)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByYou {
            Button("Manage event") { path.append(.hosted) }
        } else if event.isYouGoing {
            Button("You're in · View plans") { path.append(.registered) }
        } else if event.isFull {
            Button(event.isBookmarked ? "Watching for a spot" : "Full · Bookmark") {
                if !event.isBookmarked { store.toggleBookmark(event.id) }
            }
        } else {
            // TODO(auth): verify student email before the first RSVP. No auth in the prelim build.
            Button("RSVP Now") {
                withAnimation { store.rsvp(event.id) }
            }
        }
    }
}
