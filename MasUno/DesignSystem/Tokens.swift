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

/// Your own token from your full name (the Me card, the map, onboarding). With no name yet (a
/// guest, or before the profile loads) it shows a plain person instead of an empty circle.
struct MeToken: View {
    var name: String
    var size: CGFloat = 36
    var ring: CGFloat = 2

    var body: some View {
        let initials = PersonToken.initials(of: name)
        PersonToken(initials: initials, color: Theme.you, size: size, ring: ring)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
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
    @Environment(\.courtDecorationRuns) private var decorationRuns
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
                    // Only the angle loops: the ring's size and place, which follow the court's
                    // scale, change in the same update without being turned into a loop too.
                    .animation(isTurning ? .linear(duration: 16).repeatForever(autoreverses: false) : nil) {
                        $0.rotationEffect(.degrees(isTurning ? 360 : 0))
                    }
                    // The court springs when someone comes or goes. Without this, that spring
                    // takes the ring and the dash freezes at a bad angle.
                    .geometryGroup()
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .onAppear { isTurning = isLive && !reduceMotion && decorationRuns }
            .onDisappear { isTurning = false }
            .onChange(of: reduceMotion) { isTurning = isLive && !reduceMotion && decorationRuns }
            .onChange(of: isLive) { isTurning = isLive && !reduceMotion && decorationRuns }
            .onChange(of: decorationRuns) { isTurning = isLive && !reduceMotion && decorationRuns }
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
    /// A count that arrives before the list is left alone: cutting the tail would erase the wrong
    /// person and draw a dashed spot where they stood. A guest sees no faces, only the count.
    init(game: Game, attendees: [Attendee], me: PersonSummary?) {
        var people = attendees.map(\.person)
        if game.hidesPeople {
            people = []
            unlisted = game.goingCount
            open = game.spotsLeft
        } else if people.isEmpty {
            people = [game.host]
            if let me, game.isGoing, me.id != game.host.id { people.append(me) }
            people = Array(people.prefix(game.goingCount))
            unlisted = max(game.goingCount - people.count, 0)
            open = game.spotsLeft
        } else if people.count > game.goingCount {
            unlisted = 0
            open = max(game.capacity - people.count, 0)
        } else {
            unlisted = max(game.goingCount - people.count, 0)
            open = game.spotsLeft
        }
        self.people = people
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
        var parts = people.map { $0.id == myID ? String(localized: "You", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale) : $0.displayName }
        if unlisted > 0 {
            // With nobody named (a guest's view), "2 more" has nothing to add to.
            parts.append(people.isEmpty ? String(localized: "\(unlisted) going", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale) : String(localized: "\(unlisted) more", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale))
        }
        if open > 0 { parts.append(open == 1 ? String(localized: "1 open spot", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale) : String(localized: "\(open) open spots", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)) }
        return parts.formatted(.list(type: .and))
    }
}

/// A game's people and open spots in one row: tokens, a "+N" bubble for the people who don't fit,
/// then a dashed "+1" per open spot. Squeezes together when it runs out of width, and past
/// `TokenRowLayout.maxOverlap` shows fewer tokens: fewer spots (the last one counts the rest),
/// then fewer people (the "+N" bubble counts them).
struct TokenRow: View {
    var lineup: Lineup
    var size: CGFloat = 32
    /// Fill behind the "+1" tokens.
    var openFill: Color = .white.opacity(0.7)
    /// The row's width, once measured.
    @State private var width: CGFloat?

    private static let maxPeople = 7
    private static let maxTokens = 12

    var body: some View {
        let limit = min(Self.maxTokens, width.map { TokenRowLayout.capacity(width: $0, tokenWidth: size) } ?? Self.maxTokens)
        let showsOpen = lineup.open > 0 ? 1 : 0
        // Keeps room for at least one "+1", and for the "+N" bubble once anyone's left out.
        let shownCount = (0...min(lineup.people.count, Self.maxPeople)).last { count in
            count + (lineup.unlisted + lineup.people.count > count ? 1 : 0) + showsOpen <= limit
        } ?? 0
        let shown = lineup.people.prefix(shownCount)
        // People who are going but aren't shown (a guest sees no faces) stand as blank circles,
        // as on the court: a "+2" bubble next to the dashed "+1"s would read as two more spots.
        let blanks = (0...min(lineup.unlisted, Self.maxPeople - shown.count)).last { count in
            let left = lineup.unlisted - count + lineup.people.count - shown.count
            return shown.count + count + (left > 0 ? 1 : 0) + showsOpen <= limit
        } ?? 0
        let overflow = lineup.unlisted - blanks + lineup.people.count - shown.count
        let room = limit - shown.count - blanks - (overflow > 0 ? 1 : 0)
        let openTokens = max(0, min(lineup.open, room))

        TokenRowLayout(spacing: 3) {
            ForEach(shown) { person in
                if person.id == lineup.myID, !lineup.isHostedByMe {
                    YouToken(size: size)
                } else {
                    PersonAvatar(person: person, size: size)
                }
            }
            ForEach(0..<blanks, id: \.self) { _ in
                PersonToken(initials: "", color: .white.opacity(0.6), size: size)
            }
            if overflow > 0 { CountToken(count: overflow, size: size) }
            ForEach(0..<openTokens, id: \.self) { index in
                // The last token carries the rest when there are more spots than tokens.
                let isLast = index == openTokens - 1
                OpenSpotToken(size: size, count: isLast ? lineup.open - openTokens + 1 : 1, fill: openFill)
            }
        }
        // Takes the width it's offered, so what fits doesn't depend on what it shows.
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: lineup.accessibilityLabel))
    }
}

/// Lays tokens out left to right, 3 pt apart, and overlaps them evenly when the row is too narrow.
struct TokenRowLayout: Layout {
    var spacing: CGFloat = 3

    /// The most a token may cover the one before it, as a share of its width: about 6 pt at
    /// 32 pt, as on a 402 pt wide iPhone's Me cards. Any more and it covers the "+1" and the initials.
    static let maxOverlap: CGFloat = 0.18

    /// How many tokens `tokenWidth` wide fit in `width` without overlapping past `maxOverlap`.
    static func capacity(width: CGFloat, tokenWidth: CGFloat) -> Int {
        guard tokenWidth > 0, width > tokenWidth else { return 1 }
        return 1 + Int((width - tokenWidth) / (tokenWidth * (1 - maxOverlap)))
    }

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
