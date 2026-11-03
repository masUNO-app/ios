import SwiftUI

/// Game summary card from the Me screen (Going / Hosting): tile, title, a compact
/// trailing action, host line, date, place, status, then a footer below a divider.
struct GameCard<Accessory: View, Footer: View>: View {
    var event: SportsEvent
    var showsHost = true
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }

            if showsHost {
                HStack(spacing: 8) {
                    Avatar(name: event.host, size: 24)
                    Text("Hosted by \(event.host)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GameCardRow(systemImage: "calendar") {
                    Text(EventFormat.longDate(event.start))
                }
                GameCardRow(systemImage: "mappin") {
                    Text(verbatim: "\(event.venue.titleLine)\n\(event.venue.city)")
                }
                Text(status ?? event.statusLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)

            Divider().overlay(Theme.hairline)

            footer
        }
        .padding(16)
        .cardSurface()
    }
}

extension GameCard where Accessory == EmptyView {
    init(event: SportsEvent, showsHost: Bool = true, status: String? = nil, @ViewBuilder footer: () -> Footer) {
        self.init(event: event, showsHost: showsHost, status: status, accessory: { EmptyView() }, footer: footer)
    }
}

private struct GameCardRow<Content: View>: View {
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            content
        }
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
