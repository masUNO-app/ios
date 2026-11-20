import Foundation
import Testing
@testable import masUNO

/// The game card's one VoiceOver stop (A11Y-01): what's on the card, in reading order, with commas.
@MainActor
struct GameCardSummaryTests {
    let now = Date.now
    let world = MockFixtures.world(now: .now)

    private func game(_ id: UUID) throws -> Game {
        try #require(world.games.first { $0.id == id })
    }

    /// The card's time line as the summary reads it.
    private func spoken(_ time: String) -> String {
        time.replacingOccurrences(of: " · ", with: ", ")
    }

    @Test func aGuestCardLeavesThePeopleOut() throws {
        var game = try game(MockFixtures.GameID.open)
        game.host = .hidden
        let time = EventFormat.cardTime(game, now: now)
        let summary = game.cardSummary(
            status: game.discoverLine(now: now), time: time,
            lineup: Lineup(game: game, attendees: [], me: nil)
        )
        #expect(summary == "After-work hoops, Basketball, Room for 4 more, \(spoken(time)), Tec basketball courts, 2 going and 4 open spots")
        #expect(!summary.contains("Hosted by"))
    }

    @Test func aCancelledCardSaysWhoCancelled() throws {
        let game = try game(MockFixtures.GameID.cancelled)
        let time = EventFormat.cancelledTime(game)
        let lineup = Lineup(game: game, attendees: world.attendees[game.id] ?? [], me: world.me.summary)
        let summary = game.cardSummary(status: game.cancelledLine, time: time, lineup: lineup)
        #expect(summary == "Rainy day soccer, Soccer, Hosted by Diego M., Cancelled by Diego, \(spoken(time)), Centro Deportivo Tec, Diego M., Sam L., and 8 open spots")
    }

    @Test func aFullCardHasNoOpenSpots() throws {
        let game = try game(MockFixtures.GameID.full)
        let time = EventFormat.cardTime(game, now: now)
        let lineup = Lineup(game: game, attendees: world.attendees[game.id] ?? [], me: world.me.summary)
        let summary = game.cardSummary(status: game.roomLine, time: time, lineup: lineup)
        #expect(summary == "Padel at Distrito Tec, Padel, Hosted by Nina C., Full, \(spoken(time)), Parque Distrito Tec, Nina C., Sam L., Maya C., and Ricardo T.")
    }

    /// Hosting cards put the repost news on a second line; it's read as one more piece.
    @Test func noMiddleDotsOrLineBreaksAreRead() throws {
        let game = try game(MockFixtures.GameID.going)
        let summary = game.cardSummary(
            status: "\(game.goingLine)\nReposted just now", time: EventFormat.cardTime(game, now: now),
            lineup: Lineup(game: game, attendees: world.attendees[game.id] ?? [], me: world.me.summary)
        )
        #expect(!summary.contains("·"))
        #expect(!summary.contains("\n"))
        #expect(summary.hasPrefix("Volleyball at the arena, Volleyball, Hosted by Sam L., You're in, room for 7 more, Reposted just now, "))
    }
}
