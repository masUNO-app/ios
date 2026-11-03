import SwiftUI

/// Figma: "Popup" (341:2046) — opens from a pin on the map.
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
                    Text(event.hostLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Text(event.spotsLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
                BookmarkButton(event: event)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("\(EventFormat.dayAndTime(event.start)) · starts in \(EventFormat.countdown(to: event.start))", systemImage: "clock")
                Label(event.venue.name, systemImage: "mappin.and.ellipse")
                HStack(spacing: 8) {
                    AvatarStack(names: store.visibleAttendees(of: event), size: 22)
                    Text(store.visibleAttendees(of: event).map(Person.display).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink)
            .labelStyle(MutedIconLabelStyle())

            HStack(spacing: 10) {
                Button("Details") { appViewModel.path.append(.game(event.id)) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                primaryAction
                    .buttonStyle(.glassProminent)
                    .buttonSizing(.flexible)
            }
            .controlSize(.large)
            .fontWeight(.semibold)
        }
        .padding(16)
        .frame(maxWidth: 340, alignment: .leading)
        // Solid card, as in the Figma (glass picked up the map's colors and read as lavender).
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.dialog))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dialog).strokeBorder(Theme.hairline))
        .shadow(color: Theme.shadow, radius: 16, y: 6)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByYou {
            Button("Edit game") { appViewModel.presentGameForm(editing: event.id) }
        } else if event.isYouGoing {
            Button("View game") { appViewModel.path.append(.game(event.id)) }
        } else {
            // TODO(auth): verify student email before the first join (E5/B5).
            Button("Join game") { viewModel.join(event.id, in: store) }
        }
    }
}
