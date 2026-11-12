import SwiftUI

/// A person: initials on a color, with a white ring (SPEC §7.7.3). No profile photos.
struct PersonToken: View {
    var initials: String
    var color: Color
    var size: CGFloat = 36
    var ring: CGFloat = 2

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                Text(verbatim: initials)
                    .font(.rounded(size: size * 0.35))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, size * 0.1)
            }
            .overlay { Circle().strokeBorder(.white, lineWidth: ring) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// "Leo Park" → "LP", "Maya" → "M".
    static func initials(of name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

/// Someone else's token in their own color, or yours in `Theme.you`.
struct PersonAvatar: View {
    @Environment(\.currentUserID) private var currentUserID
    var person: PersonSummary
    var size: CGFloat = 36
    var ring: CGFloat = 2

    var body: some View {
        PersonToken(
            initials: person.initials,
            color: person.id == currentUserID ? Theme.you : person.color,
            size: size, ring: ring
        )
    }
}

/// Your own token from your full name (the Me card, the map, onboarding).
struct MeToken: View {
    var name: String
    var size: CGFloat = 36
    var ring: CGFloat = 2

    var body: some View {
        PersonToken(initials: PersonToken.initials(of: name), color: Theme.you, size: size, ring: ring)
    }
}

/// The spot you took in someone's game: a green "You".
struct YouToken: View {
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .overlay {
                Text("You")
                    .font(.rounded(size: size * 0.31))
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, size * 0.08)
            }
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The brand mark: a dashed "+1" for each open spot (SPEC §7.7.1).
struct OpenSpotToken: View {
    var size: CGFloat = 36
    /// "+1", or "+4" when a row runs out of room for one token per spot.
    var count = 1
    /// White over a sport color; clear on a plain surface.
    var fill: Color = .white.opacity(0.7)
    /// On the court the dashed ring slowly turns, so the spot looks like it's waiting for someone.
    var isLive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                Text(verbatim: "+\(count)")
                    .font(.rounded(size: size * 0.37))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .overlay {
                Circle()
                    .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .rotationEffect(.degrees(isTurning ? 360 : 0))
                    .animation(isTurning ? .linear(duration: 16).repeatForever(autoreverses: false) : nil, value: isTurning)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .onAppear { isTurning = isLive && !reduceMotion }
            .onChange(of: reduceMotion) { isTurning = isLive && !reduceMotion }
    }
}

/// "+5": people who are going but don't fit in the row.
struct CountToken: View {
    var count: Int
    var size: CGFloat = 36
    var fill: Color = Theme.separator

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                Text(verbatim: "+\(count)")
                    .font(.rounded(size: size * 0.35))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Who fills a game's spots, in order, and how many are open.
struct Lineup: Equatable {
    /// Host first, then in the order people joined. Never includes anyone you blocked.
    var people: [PersonSummary]
    /// Going but not listed: someone you blocked, or the list hasn't loaded yet.
    var unlisted: Int
    var open: Int
    var myID: UUID?
    var isHostedByMe: Bool

    /// `attendees` can be empty while Who's going loads: the host, and you if you're in, still show.
    init(game: Game, attendees: [Attendee], me: PersonSummary?) {
        var people = attendees.map(\.person)
        if people.isEmpty {
            people = [game.host]
            if let me, game.isGoing, me.id != game.host.id { people.append(me) }
        }
        people = Array(people.prefix(game.goingCount))
        self.people = people
        unlisted = max(game.goingCount - people.count, 0)
        open = game.spotsLeft
        myID = me?.id
        isHostedByMe = game.isHostedByMe
    }

    /// A made-up lineup, for the courts in onboarding.
    init(people: [PersonSummary], open: Int, myID: UUID? = nil) {
        self.people = people
        unlisted = 0
        self.open = open
        self.myID = myID
        isHostedByMe = false
    }

    /// Two people and four open spots, as in the Figma's Welcome. `includesYou` puts you in the middle.
    static func welcome(includesYou: Bool = false) -> Lineup {
        func person(_ number: UInt8, _ first: String, _ initial: String) -> PersonSummary {
            PersonSummary(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number)), firstName: first, lastInitial: initial, gradYear: 0)
        }
        let you = person(99, "", "")
        let people = [person(1, "Alex", "R"), person(6, "Ricardo", "T")] + (includesYou ? [you] : [])
        return Lineup(people: people, open: 6 - people.count, myID: includesYou ? you.id : nil)
    }

    /// "Alex R., Ricardo T. and 4 open spots", for VoiceOver.
    var accessibilityLabel: String {
        var parts = people.map { $0.id == myID ? String(localized: "You") : $0.displayName }
        if unlisted > 0 { parts.append(String(localized: "\(unlisted) more")) }
        if open > 0 { parts.append(open == 1 ? String(localized: "1 open spot") : String(localized: "\(open) open spots")) }
        return parts.formatted(.list(type: .and))
    }
}

/// A game's people and open spots in one row: tokens, a "+N" bubble for the people who don't fit,
/// then a dashed "+1" per open spot. Squeezes together when it runs out of width.
struct TokenRow: View {
    var lineup: Lineup
    var size: CGFloat = 32
    /// Fill behind the "+1" tokens.
    var openFill: Color = .white.opacity(0.7)

    private static let maxPeople = 7
    private static let maxTokens = 12

    var body: some View {
        let shown = lineup.people.prefix(Self.maxPeople)
        let overflow = lineup.unlisted + lineup.people.count - shown.count
        let room = Self.maxTokens - shown.count - (overflow > 0 ? 1 : 0)
        let openTokens = min(lineup.open, room)

        TokenRowLayout(spacing: 3) {
            ForEach(shown) { person in
                if person.id == lineup.myID, !lineup.isHostedByMe {
                    YouToken(size: size)
                } else {
                    PersonAvatar(person: person, size: size)
                }
            }
            if overflow > 0 { CountToken(count: overflow, size: size) }
            ForEach(0..<openTokens, id: \.self) { index in
                // The last token carries the rest when there are more spots than tokens.
                let isLast = index == openTokens - 1
                OpenSpotToken(size: size, count: isLast ? lineup.open - openTokens + 1 : 1, fill: openFill)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: lineup.accessibilityLabel))
    }
}

/// Lays tokens out left to right, 3 pt apart, and overlaps them evenly when the row is too narrow.
struct TokenRowLayout: Layout {
    var spacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: min(natural, proposal.width ?? natural), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let width = first.sizeThatFits(.unspecified).width
        let steps = CGFloat(max(subviews.count - 1, 1))
        let step = min(width + spacing, (bounds.width - width) / steps)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * step, y: bounds.minY),
                proposal: .unspecified
            )
        }
    }
}

/// Overlapping tokens with a "+N" bubble, for tight spots: under map pins and in the chat header.
struct TokenStack: View {
    var people: [PersonSummary]
    /// People beyond `people` (e.g. the rest of a game's going count).
    var extra = 0
    var maxVisible = 3
    var size: CGFloat = 24
    var ring: CGFloat = 1.5

    var body: some View {
        let visible = people.prefix(maxVisible)
        let overflow = extra + people.count - visible.count

        HStack(spacing: -size * 0.22) {
            ForEach(visible) { PersonAvatar(person: $0, size: size, ring: ring) }
            if overflow > 0 {
                CountToken(count: overflow, size: size, fill: Theme.accentSoft)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: people.map(\.displayName).formatted(.list(type: .and))))
    }
}
