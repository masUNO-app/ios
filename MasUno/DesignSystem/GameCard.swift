import SwiftUI

/// Game summary card from Me (Going / Hosting): tile, title, a compact trailing action,
/// host line, date, place and status. An optional footer goes below a divider.
struct GameCard<Accessory: View, Footer: View>: View {
    var event: SportsEvent
    var showsHost = true
    /// Overrides the status line (e.g. "3 going · 3 spots left" on Hosting).
    var status: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ActivityTile(sport: event.sport)
                Text(event.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }

            if showsHost {
                HStack(spacing: 8) {
                    Avatar(name: event.host, size: 24)
                    Text("Hosted by \(Person.display(event.host))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(EventFormat.dayAndTime(event.start), systemImage: "calendar")
                Label {
                    Text(verbatim: "\(event.venue.name) · \(event.venue.street)")
                } icon: {
                    Image(systemName: "mappin")
                }
                if event.isCancelled {
                    StatusChip(String(localized: "Cancelled"))
                        .padding(.top, 2)
                } else {
                    Text(status ?? event.openLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 2)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .labelStyle(MutedIconLabelStyle())

            if Footer.self != EmptyView.self {
                Divider().overlay(Theme.hairline)
                footer
            }
        }
        .padding(16)
        .cardSurface()
    }
}

extension GameCard where Footer == EmptyView {
    init(event: SportsEvent, showsHost: Bool = true, status: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.init(event: event, showsHost: showsHost, status: status, accessory: accessory, footer: { EmptyView() })
    }
}

/// Label with a muted, fixed-width icon so rows line up.
struct MutedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Theme.muted).frame(width: 16)
            configuration.title
        }
    }
}
