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
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("\(EventFormat.dayAndTime(event.start)) · starts in \(EventFormat.countdown(to: event.start))", systemImage: "clock")
                Label(event.venue.name, systemImage: "mappin.and.ellipse")
                HStack(spacing: 8) {
                    AvatarStack(names: event.attendees, size: 22)
                    Text(event.attendees.map(Person.display).joined(separator: ", "))
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
        // Card-tinted glass keeps text legible over the map while picking up its colors.
        .glassEffect(.regular.tint(Theme.card.opacity(0.85)), in: .rect(cornerRadius: Theme.Radius.dialog))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if event.isHostedByYou {
            Button("Edit game") { appViewModel.startAdding(editing: event.id) }
        } else if event.isYouGoing {
            Button("View game") { appViewModel.path.append(.game(event.id)) }
        } else {
            // TODO(auth): verify student email before the first join (E5/B5).
            Button("Join game") { viewModel.join(event.id, in: store) }
        }
    }
}
