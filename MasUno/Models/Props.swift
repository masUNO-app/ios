import Foundation

/// One of the four things people can say about someone they played with (1.0, `docs/API.md`
/// "Props"). The same four for every sport and esport, only good things, never about skill.
nonisolated enum Prop: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case goodSport = "good_sport"
    case onTime = "on_time"
    case teamPlayer = "team_player"
    case madeItFun = "made_it_fun"

    var id: String { rawValue }

    @MainActor var name: String {
        switch self {
        case .goodSport: String.app("Good sport")
        case .onTime: String.app("On time")
        case .teamPlayer: String.app("Team player")
        case .madeItFun: String.app("Made it fun")
        }
    }
}

/// Someone you can give props to after a plan or a round (`props_to_give`).
nonisolated struct PropsPeer: Identifiable, Hashable, Sendable {
    var person: PersonSummary
    var isHost: Bool
    /// Earlier plans you were both in.
    var playedBefore: Int
    /// What you already sent them for this plan or round.
    var sent: Set<Prop>

    var id: UUID { person.id }
}

/// The props sheet's data: whether it's open, until when, and who you played with.
nonisolated struct PropsToGive: Hashable, Sendable {
    var isOpen: Bool
    var opensAt: Date?
    var closesAt: Date?
    var people: [PropsPeer]

    static let closed = PropsToGive(isOpen: false, opensAt: nil, closesAt: nil, people: [])

    /// People you've sent at least one prop to.
    var sentCount: Int { people.filter { !$0.sent.isEmpty }.count }
}

/// The props you got for one plan (`my_props_for_game`): counts of different people, never who.
nonisolated struct PropTally: Hashable, Sendable {
    var people: Int
    var counts: [Prop: Int]

    static let empty = PropTally(people: 0, counts: [:])

    /// Most first, in the props' own order for ties.
    var ranked: [(prop: Prop, count: Int)] {
        Prop.allCases.compactMap { prop in counts[prop].map { (prop, $0) } }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }
}

/// One campus's top people for a prop this month (`props_leaderboard`).
nonisolated struct PropsLeaderboard: Hashable, Sendable {
    nonisolated struct Entry: Identifiable, Hashable, Sendable {
        var rank: Int
        var person: PersonSummary
        /// Different people who gave them this prop this month.
        var people: Int
        /// The activity slug most of their props came from.
        var mostly: String?

        var id: UUID { person.id }
    }

    /// The first day of the month counted.
    var month: Date
    var resetsAt: Date
    var top: [Entry]
    /// You're shown on the list.
    var isOptedIn: Bool
    /// Your rank as if listed; nil with no props this month.
    var myRank: Int?
    var myPeople: Int

    /// "2 more for the top 10": how many more people you'd need, or nil when you're in it already
    /// or there's no 10th place yet.
    var neededForTopTen: Int? {
        guard myRank.map({ $0 > 10 }) ?? true, top.count >= 10 else { return nil }
        return max(1, top[9].people - myPeople + 1)
    }
}
