import Foundation

/// A round night: one game played in rounds, with a break between them and new groups each round,
/// so everyone plays with as many new people as the night allows. The game's own start and end
/// span every round. Mock only for now: `create_game` has no rotation yet.
nonisolated struct Rotation: Hashable, Sendable {
    static let roundCounts = [2, 3, 4, 5]
    /// No round goes past an hour.
    static let roundLengths = [30, 45, 60]
    static let breakLengths = [10, 15, 20, 30]
    static let groupSizes = [2, 3, 4, 5, 6]
    static let standard = Rotation(rounds: 3, roundMinutes: 60, breakMinutes: 20, groupSize: 4)

    var rounds: Int
    var roundMinutes: Int
    var breakMinutes: Int
    /// People per group. Leftovers join groups one each, so a group can have one more.
    var groupSize: Int

    /// The whole night, first round to last: the game's duration.
    var totalMinutes: Int {
        rounds * roundMinutes + (rounds - 1) * breakMinutes
    }

    var isValid: Bool {
        Self.roundCounts.contains(rounds) && Self.roundLengths.contains(roundMinutes)
            && Self.breakLengths.contains(breakMinutes) && Self.groupSizes.contains(groupSize)
    }

    /// Fewest players for two groups, without which nobody rotates.
    var minimumPlayers: Int { groupSize * 2 }

    /// - Parameter round: 0 for the first.
    func start(of round: Int, from gameStart: Date) -> Date {
        gameStart.addingTimeInterval(Double(round * (roundMinutes + breakMinutes)) * 60)
    }

    func end(of round: Int, from gameStart: Date) -> Date {
        start(of: round, from: gameStart).addingTimeInterval(Double(roundMinutes) * 60)
    }

    /// When a round's groups are picked and shown: the first at the start, the rest as the break
    /// before them begins, so people who join late still get mixed in.
    func reveal(of round: Int, from gameStart: Date) -> Date {
        round == 0 ? gameStart : end(of: round - 1, from: gameStart)
    }

    /// How many groups `players` people make, at least one.
    func groupCount(players: Int) -> Int {
        max(1, players / groupSize)
    }

    /// The most new people one player can meet over the night, with nobody twice.
    func mostNewPeople(players: Int) -> Int {
        max(0, min(rounds * (groupSize - 1), players - 1))
    }
}

/// One round as the server hands it out.
nonisolated struct RotationRound: Identifiable, Hashable, Sendable {
    /// 0 for the first.
    let index: Int
    let startsAt: Date
    let endsAt: Date
    /// When the groups come out. Until then `groups` is nil.
    let revealsAt: Date
    /// Each group's people, by station: the first group plays at station 1. Nil until revealed;
    /// never anyone you blocked.
    var groups: [[PersonSummary]]?

    var id: Int { index }
}

/// A round night's rounds, in order.
nonisolated struct RotationPlan: Hashable, Sendable {
    var rounds: [RotationRound]

    /// Where `person` plays in a round: the station (from 1) and the rest of the group.
    func group(of person: UUID, in round: RotationRound) -> (station: Int, people: [PersonSummary])? {
        guard let groups = round.groups,
              let index = groups.firstIndex(where: { $0.contains { $0.id == person } })
        else { return nil }
        return (index + 1, groups[index].filter { $0.id != person })
    }

    /// Everyone `person` has played with so far, in the order they met, each once.
    func peopleMet(by person: UUID) -> [PersonSummary] {
        var seen: Set<UUID> = [person]
        var met: [PersonSummary] = []
        for round in rounds {
            for other in group(of: person, in: round)?.people ?? [] where seen.insert(other.id).inserted {
                met.append(other)
            }
        }
        return met
    }
}

/// Picks a round's groups so people meet as many new faces as possible. Deterministic for a seed,
/// so the same night always shuffles the same way.
nonisolated enum RotationPlanner {
    /// - Parameters:
    ///   - ids: Everyone playing this round.
    ///   - size: The rotation's group size.
    ///   - earlier: The groups of the rounds already played.
    ///   - seed: Varies the shuffle; pass the same one to get the same groups.
    /// - Returns: Groups as even as the numbers allow, with as few people who already played
    ///   together as the tries found.
    static func groups(of ids: [UUID], size: Int, earlier: [[[UUID]]], seed: UInt64) -> [[UUID]] {
        guard !ids.isEmpty else { return [] }
        let count = max(1, ids.count / max(size, 1))
        let base = ids.count / count
        let capacities = (0..<count).map { base + ($0 < ids.count % count ? 1 : 0) }
        var met: [UUID: Set<UUID>] = [:]
        for group in earlier.joined() {
            for id in group { met[id, default: []].formUnion(group.filter { $0 != id }) }
        }

        var generator = SplitMix64(seed: seed)
        var best: (groups: [[UUID]], repeats: Int)?
        // Greedy fill from a few shuffles; keep the one with the fewest repeat pairs.
        for _ in 0..<48 {
            var groups = Array(repeating: [UUID](), count: count)
            var repeats = 0
            for id in ids.shuffled(using: &generator) {
                let known = met[id] ?? []
                let pick = groups.indices
                    .filter { groups[$0].count < capacities[$0] }
                    .min { a, b in
                        let left = (groups[a].filter(known.contains).count, groups[a].count, a)
                        let right = (groups[b].filter(known.contains).count, groups[b].count, b)
                        return left < right
                    }!
                repeats += groups[pick].filter(known.contains).count
                groups[pick].append(id)
            }
            if best.map({ repeats < $0.repeats }) ?? true { best = (groups, repeats) }
            if repeats == 0 { break }
        }
        return best!.groups
    }

    /// A seed from a game and a round.
    static func seed(game: UUID, round: Int) -> UInt64 {
        let bytes = withUnsafeBytes(of: game.uuid) { Array($0) }
        let high = bytes.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = bytes.suffix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return high ^ low ^ (UInt64(round + 1) &* 0x9E37_79B9_7F4A_7C15)
    }
}

/// A small seeded generator, so shuffles repeat for the same seed.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
