#if DEBUG
import SwiftUI

/// Every 1.0 token and component on one screen, for design review with Arianna.
/// Open it by long-pressing the avatar on the map, or launch with `-screen gallery`.
struct ComponentGallery: View {
    @State private var name = ""
    @State private var showsDialog = false
    @State private var isOn = true

    private let swatches: [(String, Color)] = [
        ("accent", Theme.accent), ("accentSoft", Theme.accentSoft),
        ("background", Theme.background), ("card", Theme.card), ("surface2", Theme.surface2),
        ("ink", Theme.ink), ("muted", Theme.muted), ("mutedLarge", Theme.mutedLarge),
        ("destructive", Theme.destructive), ("error", Theme.error),
        ("you", Theme.you), ("separator", Theme.separator),
    ]

    private var game: Game { MockFixtures.world(now: .now).games[0] }
    private var lineup: Lineup { Lineup(game: game, attendees: MockFixtures.world(now: .now).attendees[game.id] ?? [], me: nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Colors") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        ForEach(swatches, id: \.0) { name, color in swatch(name, color) }
                        ForEach(Activity.builtIn) { swatch($0.slug, $0.color) }
                    }
                }

                section("Text") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "After-work hoops").font(.rounded(.title, .bold))
                        Text(verbatim: "Room for 4 more").font(.rounded(.headline, .bold))
                        Text(verbatim: "Casual 3-on-3 after work. Bring a ball if you have one.").font(.rounded(.subheadline))
                        Text(verbatim: "Starts in 35 min · about 1 hour").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                }

                section("Pills") {
                    VStack(spacing: 12) {
                        Button(String("Primary")) {}.pill(.primary)
                        Button(String("Secondary")) {}.pill(.secondary)
                        Button(String("Destructive")) { showsDialog = true }.pill(.destructive)
                        Button(String("Quiet")) {}.pill(.quiet)
                        Button(String("Quiet destructive")) {}.pill(.quietDestructive)
                        Button(String("Disabled")) {}.pill(.primary).disabled(true)
                        HStack(spacing: 12) {
                            Button(String("Leave")) {}.pill(.secondary, expands: false)
                            Button(String("Change")) {}.pill(.secondary, expands: false, size: .regular)
                            Button(String("Edit")) {}.pill(.secondary, expands: false, size: .small)
                            Button(String("Close"), systemImage: "xmark") {}.glassCircle()
                            Spacer()
                        }
                    }
                }

                section("Tokens") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ForEach(lineup.people) { PersonAvatar(person: $0, size: 44) }
                            MeToken(name: "Emilio Garza", size: 44)
                            YouToken(size: 44)
                            OpenSpotToken(size: 44, fill: .clear)
                            CountToken(count: 5, size: 44)
                        }
                        TokenRow(lineup: lineup, size: 32, openFill: .clear)
                        TokenStack(people: lineup.people, extra: 3, size: 30, ring: 2)
                    }
                }

                section("Chips & tiles") {
                    VStack(alignment: .leading, spacing: 12) {
                        FlowLayout(spacing: 8) {
                            ForEach(Activity.builtIn) { SportChip(sport: $0) }
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(Activity.builtIn) { sport in
                                SportToggle(sport: sport, isOn: isOn && sport.sortOrder.isMultiple(of: 2)) { isOn.toggle() }
                            }
                        }
                        HStack(spacing: 12) {
                            ForEach(Activity.builtIn) { ActivityTile(sport: $0) }
                            IconTile(systemImage: "mappin.and.ellipse", color: Color(.sportVolleyball).opacity(0.45))
                        }
                        HStack(spacing: 12) {
                            VerifiedBadge().padding(8).background(Theme.you, in: .capsule)
                            OptionalTag()
                        }
                    }
                }

                section("Pins") {
                    HStack(alignment: .bottom, spacing: 20) {
                        ForEach(Activity.builtIn) { sport in
                            PinMarker(color: sport.color) { Text(sport.emoji).font(.system(size: 24)) }
                        }
                    }
                }

                section("Courts") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Activity.builtIn) { sport in
                                CourtHeader(activity: sport, lineup: .welcome(includesYou: true), capacity: sport.slug == "soccer" ? 10 : 6, scale: 0.6)
                                    .frame(width: CourtArt.designWidth * 0.6)
                                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                section("Fields") {
                    VStack(spacing: 12) {
                        FieldBox("Game name") {
                            TextField(text: $name) { Text(verbatim: "e.g. After-work hoops") }
                        }
                        FieldBox("Game name", error: "Add a name so people know what they're joining.") {
                            Text(verbatim: "e.g. After-work hoops").foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 10) {
                            FieldBox("Date", showsChevron: true) { Text(verbatim: "Sat, Oct 24") }
                            FieldBox("Start time", isInvalid: true, showsChevron: true) { Text(verbatim: "9:00 AM") }
                        }
                        OptionRow(title: "Made me feel unsafe", isSelected: isOn) { isOn.toggle() }
                    }
                }

                section("Game card") {
                    GameCard(event: game, lineup: lineup, status: game.roomLine, time: EventFormat.cardTime(game)) {
                        Button(String("Details")) {}.pill(.secondary, expands: false)
                        Button(String("Count me in")) {}.pill(.primary)
                    }
                    GameCard(event: game, lineup: lineup, status: game.cancelledLine, time: EventFormat.cancelledTime(game), isMuted: true) {
                        Button(String("Remove")) {}.pill(.secondary, expands: false)
                        Button(String("Find another game")) {}.pill(.primary)
                    }
                }

                section("States") {
                    EmptyCard(title: "No games yet", message: "Find one nearby, or start your own. Most games just need one more.") {
                        Button(String("Find a game")) {}.pill(.primary)
                    }
                    SafetyNote(text: "Anything feel off? Tap ••• next to anyone to report or block them. Only the masUNO team sees reports.")
                    RetryCard {}
                    OfflineBanner()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
            .readableColumn()
        }
        .background(Theme.background)
        .navigationTitle(Text(verbatim: "Component gallery"))
        .navigationBarTitleDisplayMode(.inline)
        .dialog(isPresented: $showsDialog) {
            DialogCard(
                systemImage: "trash", tone: .destructive,
                title: Text(verbatim: "Cancel Sunday pickup soccer?"),
                message: Text(verbatim: "We'll let the 3 people who joined know it's cancelled and close the group chat."),
                footnote: Text(verbatim: "This can't be undone."),
                confirm: DialogAction("Cancel game"),
                cancel: DialogAction("Keep game")
            )
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
            Text(verbatim: name).font(.rounded(.caption)).foregroundStyle(Theme.muted)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title)
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
            content()
        }
    }
}

#Preview {
    NavigationStack { ComponentGallery() }
}
#endif
