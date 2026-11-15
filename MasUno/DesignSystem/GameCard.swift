import SwiftUI

/// The 1.0 game card (SPEC §7.7.3): a header in the sport's color with the sport line, title,
/// one status line and the people + "+1" tokens; then time and place; then up to two actions.
/// The map popup, Me (Going / Hosting / Earlier), Saved games and Invite a friend all use it.
struct GameCard<Accessory: View, Actions: View>: View {
    var event: Game
    var lineup: Lineup
    /// "Room for 4 more", "You're in · room for 3 more", "3 joined · room for 6 more"…
    var status: String
    /// "Today, 7:35 PM · starts in 35 min".
    var time: String
    /// Grey header instead of the sport's color: cancelled and past games.
    var isMuted = false
    /// Floating cards (the map popup, sheets) lift off what's behind them.
    var isFloating = false
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            details
            if Actions.self != EmptyView.self {
                Theme.separator.frame(height: 1)
                HStack(spacing: 10) { actions }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.dialog))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dialog).strokeBorder(Theme.separator))
        .shadow(color: Theme.ink.opacity(isFloating ? 0.22 : 0.08), radius: isFloating ? 14 : 5, y: isFloating ? 8 : 2)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(event.activity.emoji)
                    .font(.system(size: 18))
                    .saturation(isMuted ? 0 : 1)
                Text(verbatim: event.hostLine)
                    .font(.rounded(.footnote))
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title)
                        .font(.rounded(.title2, .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: status)
                        .font(.rounded(.subheadline))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }

            TokenRow(lineup: lineup, size: 32, openFill: .white.opacity(isMuted ? 0.9 : 0.7))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMuted ? Theme.separator : event.activity.color)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: time)
            } icon: {
                Image(systemName: "clock")
            }
            Label {
                Text(verbatim: event.place.name)
            } icon: {
                PlaceIcon(size: 17)
            }
        }
        .font(.rounded(.subheadline))
        .foregroundStyle(Theme.ink)
        .labelStyle(IconRowLabelStyle())
        .lineLimit(1)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension GameCard where Accessory == EmptyView {
    init(
        event: Game, lineup: Lineup, status: String, time: String, isMuted: Bool = false,
        isFloating: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            event: event, lineup: lineup, status: status, time: time, isMuted: isMuted,
            isFloating: isFloating, accessory: { EmptyView() }, actions: actions
        )
    }
}

extension GameCard where Accessory == EmptyView, Actions == EmptyView {
    init(event: Game, lineup: Lineup, status: String, time: String, isFloating: Bool = false) {
        self.init(
            event: event, lineup: lineup, status: status, time: time, isFloating: isFloating,
            accessory: { EmptyView() }, actions: { EmptyView() }
        )
    }
}

/// The popup's tail: a small rounded point from the card's bottom edge down to its pin.
nonisolated struct CalloutTail: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: tip.x + 2.6, y: tip.y - 2.2))
        path.addQuadCurve(to: CGPoint(x: tip.x - 2.6, y: tip.y - 2.2), control: tip)
        path.closeSubpath()
        return path
    }
}
