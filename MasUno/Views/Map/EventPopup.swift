import SwiftUI

/// Figma: "Basketball Game Pop-up" in "Sports event map · Popup".
struct EventPopup: View {
    @Environment(EventStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    var event: SportsEvent
    var viewModel: EventMapViewModel

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
                    Text("\(event.sport.name) · Hosted by \(event.host)")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Text(event.statusLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
                Button(
                    event.isBookmarked ? "Remove bookmark" : "Bookmark",
                    systemImage: event.isBookmarked ? "bookmark.fill" : "bookmark"
                ) {
                    viewModel.toggleBookmark(event.id, in: store)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(Theme.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("\(event.start.formatted(date: .omitted, time: .shortened)) · starts in \(EventFormat.countdown(to: event.start))", systemImage: "clock")
                Label(event.venue.fullAddress, systemImage: "mappin.and.ellipse")
                if !event.attendees.isEmpty {
                    HStack(spacing: 8) {
                        AvatarStack(names: event.attendees, size: 22)
                        Text(event.attendees.joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink)
            .labelStyle(MutedIconLabelStyle())

            primaryAction
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonSizing(.flexible)
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        // Card-tinted glass keeps text legible over the map while picking up its colors.
        .glassEffect(.regular.tint(Theme.card.opacity(0.85)), in: .rect(cornerRadius: Theme.Radius.dialog))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByYou {
            Button("Manage game") { appViewModel.path.append(.hosted) }
        } else if event.isYouGoing {
            Button("You're in · View plans") { appViewModel.path.append(.registered) }
        } else if event.isFull {
            Button(event.isBookmarked ? "Watching for a spot" : "Full · Bookmark") {
                if !event.isBookmarked { viewModel.toggleBookmark(event.id, in: store) }
            }
        } else {
            // TODO(auth): verify student email before the first RSVP. No auth in the prelim build.
            Button("Join game") {
                viewModel.rsvp(event.id, in: store)
            }
        }
    }
}
