import SwiftUI

/// Props on an ended plan you were in (design canvas, screen 2): who you played with and a way into
/// the props sheet while it's open, then the props you got and the campus leaderboard. A round night
/// gives props round by round in `RotationSection`, so here it only shows what you got.
struct PropsRecapSection: View {
    @Environment(GameStore.self) private var store
    var event: Game

    @State private var props: PropsToGive?
    @State private var tally: PropTally?
    @State private var givesProps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let props, props.isOpen, !props.people.isEmpty { giveCard(props) }
            if let tally, tally.people > 0 { gotCard(tally) }
        }
        .task(id: event.id) {
            await load()
            #if DEBUG
            // `-screen props-sheet` (with `-esports YES`): the sheet over the plan that just ended.
            if UserDefaults.standard.string(forKey: "screen") == "props-sheet", props?.isOpen == true { givesProps = true }
            #endif
        }
        .sheet(isPresented: $givesProps, onDismiss: { Task { await load() } }) {
            PropsSheet(gameID: event.id)
        }
    }

    private func load() async {
        if event.rotation == nil { props = try? await store.propsToGive(event.id) }
        tally = try? await store.myProps(event.id)
    }

    // MARK: Give

    private func giveCard(_ props: PropsToGive) -> some View {
        let newPeople = props.people.filter { $0.playedBefore == 0 }.count
        let left = props.people.count - props.sentCount

        return VStack(alignment: .leading, spacing: 14) {
            Text(newPeople > 0
                 ? "You played with \(props.people.count) people, \(newPeople) new"
                 : "You played with \(props.people.count) people")
                .font(.rounded(.title3, .bold))
                .foregroundStyle(Theme.ink)
            FlowLayout(spacing: 12) {
                ForEach(props.people) { peer in
                    VStack(spacing: 4) {
                        PersonAvatar(person: peer.person, size: 44)
                            .overlay(alignment: .bottomTrailing) {
                                if !peer.sent.isEmpty {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(Theme.onAccent)
                                        .frame(width: 20, height: 20)
                                        .background(Theme.accent, in: .circle)
                                        .overlay { Circle().strokeBorder(Theme.card, lineWidth: 2) }
                                        .offset(x: 4, y: 4)
                                }
                            }
                        Text(verbatim: peer.person.firstName)
                            .font(.rounded(.caption, .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .frame(width: 58)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: peer.sent.isEmpty
                        ? peer.person.firstName
                        : String.app("\(peer.person.firstName), props sent")))
                }
            }
            Button(left == 0 ? String.app("Change your props") : left == props.people.count
                   ? String.app("Give props") : String.app("Give props to \(left) more")) {
                givesProps = true
            }
            .pill(left == 0 ? .secondary : .primary)
            if let closes = props.closesAt {
                Text("Open until \(EventFormat.dayAndTime(closes))")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.activity.color.opacity(0.22), in: .rect(cornerRadius: 20))
    }

    // MARK: Got

    private func gotCard(_ tally: PropTally) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Props you got")
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(tally.people == 1 ? "from 1 person" : "from \(tally.people) people")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
            FlowLayout(spacing: 8) {
                ForEach(tally.ranked, id: \.prop) { entry in
                    PropCount(prop: entry.prop, count: entry.count, tint: event.activity.color)
                }
            }
            RowDivider()
            NavigationLink(value: Route.leaderboard) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.tile))
                        .accessibilityHidden(true)
                    Text("Top teammates on campus")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text("See all")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// "Good sport 4": a prop and how many different people gave it, in Liquid Glass like `SportChip`.
struct PropCount: View {
    var prop: Prop
    var count: Int
    /// The plan's sport color.
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: prop.name)
            Text(verbatim: "\(count)")
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Theme.ink.opacity(0.1), in: .capsule)
        }
        .font(.rounded(.footnote, .bold))
        .foregroundStyle(Theme.ink)
        .inkOnColor()
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .appGlass(in: .capsule, tint: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: count == 1
            ? String.app("\(prop.name), from 1 person")
            : String.app("\(prop.name), from \(count) people")))
    }
}
