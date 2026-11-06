import SwiftUI

/// Game summary card from Me (Going / Hosting): tile, title, a compact trailing action,
/// host line, date, place and status. An optional footer goes below a divider.
struct GameCard<Accessory: View, Footer: View>: View {
    var event: Game
    var showsHost = true
    /// Overrides the status line (e.g. "3 going · 3 spots left" on Hosting).
    var status: String?
    /// Hosting cards: "Auto-repost on" / "Reposted 5 min ago".
    var showsRepost = false
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ActivityTile(sport: event.activity)
                Text(event.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }

            if showsHost {
                HStack(spacing: 8) {
                    Avatar(name: event.host.displayName, size: 24)
                    Text("Hosted by \(event.host.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(EventFormat.dayAndTime(event.startsAt), systemImage: "calendar")
                Label {
                    Text(verbatim: event.place.titleLine)
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
                if showsRepost, event.autoRepost, !event.isCancelled {
                    Label(repostLine, systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
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

extension GameCard {
    private var repostLine: String {
        guard let repostedAt = event.repostedAt else { return String(localized: "Auto-repost on") }
        return String(localized: "Reposted \(repostedAt.formatted(.relative(presentation: .named)))")
    }
}

extension GameCard where Footer == EmptyView {
    init(event: Game, showsHost: Bool = true, status: String? = nil, @ViewBuilder accessory: () -> Accessory) {
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
