import Foundation
import Testing
@testable import masUNO

/// Props after a plan (1.0): the mock follows the server's rules (who, when, round-night groups), and
/// the live rows decode what `docs/API.md` "Props" says the RPCs return.
@MainActor
struct PropsTests {
    typealias IDs = MockFixtures.GameID

    // MARK: Mock rules

    @Test func propsOpenAfterAPlanForEveryoneThere() async throws {
        let backend = MockBackend(esports: true)
        let props = try await backend.propsToGive(gameID: IDs.justEnded, round: nil)
        #expect(props.isOpen)
        #expect(props.people.count == 7)
        #expect(props.people.first?.isHost == true)
        #expect(!props.people.contains { $0.id == backend.me.id })
        // Alex was in the morning hoops fixture too.
        #expect(props.people.first { $0.id == MockFixtures.alex.id }?.playedBefore ?? 0 >= 1)
        #expect(try #require(props.closesAt) > backend.now)
    }

    @Test func sendingReplacesWhatWasSent() async throws {
        let backend = MockBackend(esports: true)
        let alex = MockFixtures.alex.id, diego = MockFixtures.diego.id
        #expect(try await backend.giveProps(gameID: IDs.justEnded, round: nil, [alex: [.goodSport, .onTime], diego: [.teamPlayer]]) == 3)
        #expect(try await backend.giveProps(gameID: IDs.justEnded, round: nil, [alex: []]) == 1)
        let props = try await backend.propsToGive(gameID: IDs.justEnded, round: nil)
        #expect(props.people.first { $0.id == alex }?.sent == [])
        #expect(props.people.first { $0.id == diego }?.sent == [.teamPlayer])
        #expect(props.sentCount == 1)
    }

    @Test func onlyPeopleYouPlayedWith() async throws {
        let backend = MockBackend(esports: true)
        await #expect(throws: DomainError.invalidInput) {
            try await backend.giveProps(gameID: IDs.justEnded, round: nil, [MockFixtures.esportsPlayers[0].id: [.goodSport]])
        }
    }

    @Test func aDayAfterPropsAreClosed() async throws {
        let backend = MockBackend(esports: true)
        // The morning hoops fixture ended 25 hours ago.
        #expect(try await backend.propsToGive(gameID: IDs.ended, round: nil).isOpen == false)
        await #expect(throws: DomainError.propsClosed) {
            try await backend.giveProps(gameID: IDs.ended, round: nil, [MockFixtures.alex.id: [.goodSport]])
        }
    }

    @Test func roundNightsGivePropsToYourGroupEachRound() async throws {
        let backend = MockBackend(esports: true)
        // Round 1 is over and round 2 is on: props for round 1 are open, for round 2 not yet.
        let first = try await backend.propsToGive(gameID: IDs.roundNight, round: 0)
        #expect(first.isOpen)
        #expect(first.people.count == Rotation.standard.groupSize - 1)
        #expect(try await backend.propsToGive(gameID: IDs.roundNight, round: 1).isOpen == false)
        #expect(try await backend.propsToGive(gameID: IDs.roundNight, round: nil).isOpen == false)
    }

    @Test func whoIsGoingShowsTopProps() async throws {
        let backend = MockBackend(esports: true)
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "PropsTests.\(UUID().uuidString)")!
        )
        await store.loadPropCounts(for: [MockFixtures.alex.id, MockFixtures.sam.id])
        #expect(store.topProp(of: MockFixtures.alex.id)?.prop == .onTime)
        #expect(store.topProp(of: MockFixtures.alex.id)?.people == 15)
        // Fewer than 3 givers: nothing to show, but asked, so the row can say "New here".
        #expect(store.topProp(of: MockFixtures.sam.id) == nil)
        #expect(store.hasPropCounts(for: MockFixtures.sam.id))
    }

    @Test func leaderboardFiltersAndOptIn() async throws {
        let backend = MockBackend(esports: true)
        let all = try await backend.propsLeaderboard(prop: .goodSport, filter: nil)
        #expect(all.top.first?.rank == 1)
        #expect(!all.isOptedIn)
        let esports = try await backend.propsLeaderboard(prop: .goodSport, filter: Activity.esportsKind)
        #expect(!esports.top.isEmpty)
        #expect(esports.top.allSatisfy { $0.mostly == "valorant" })
        #expect(try await backend.setPropsLeaderboardOptIn(true))
        #expect(try await backend.propsLeaderboard(prop: .goodSport, filter: nil).isOptedIn)
    }

    @Test func neededForTopTen() {
        let person = MockFixtures.alex
        let top = (1...10).map { PropsLeaderboard.Entry(rank: $0, person: person, people: 20 - $0, mostly: nil) }
        let board = PropsLeaderboard(month: .now, resetsAt: .now, top: top, isOptedIn: false, myRank: 14, myPeople: 6)
        // The 10th has 10 people; 6 + 5 passes them.
        #expect(board.neededForTopTen == 5)
        var inIt = board
        inIt.myRank = 3
        #expect(inIt.neededForTopTen == nil)
    }

    // MARK: Live rows

    private func decode<Row: Decodable>(_ json: String) throws -> Row {
        try JSONDecoder().decode(Row.self, from: Data(json.utf8))
    }

    @Test func propsToGiveDecodes() throws {
        let response: PropsToGiveResponse = try decode("""
        {"open":true,"opens_at":"2026-11-24T19:30:00+00:00","closes_at":"2026-11-25T19:30:00+00:00",
         "people":[{"id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","first_name":"Lucía","last_initial":"M","grad_year":2026,
                    "is_host":true,"played_before":2,"sent":["on_time","best_player"]}]}
        """)
        let props = response.props
        #expect(props.isOpen)
        #expect(props.people.first?.person.displayName == "Lucía M.")
        #expect(props.people.first?.playedBefore == 2)
        // A prop this build doesn't know is left out.
        #expect(props.people.first?.sent == [.onTime])

        let closed: PropsToGiveResponse = try decode(#"{"open":false,"opens_at":null,"closes_at":null,"people":[]}"#)
        #expect(closed.props == .closed)
    }

    @Test func givePropsSendsLowercaseIDsAndProps() throws {
        let id = UUID(uuidString: "0B7E4B8C-1111-4C3D-9A2B-123456789ABC")!
        let params = PropsParams(gameID: id, round: nil, props: [id.uuidString.lowercased(): ["good_sport"]])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        #expect(json["p_round"] is NSNull)
        #expect((json["p_props"] as? [String: [String]])?["0b7e4b8c-1111-4c3d-9a2b-123456789abc"] == ["good_sport"])
    }

    @Test func countsAndLeaderboardDecode() throws {
        let rows: [PropCountRow] = try decode("""
        [{"user_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","prop":"good_sport","people":9},
         {"user_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","prop":"made_it_fun","people":3}]
        """)
        let counts = PropCountRow.counts(rows)
        #expect(counts.values.first?[.goodSport] == 9)

        let tally: MyPropsResponse = try decode(#"{"people":5,"props":{"good_sport":4,"on_time":2}}"#)
        #expect(tally.tally.ranked.map(\.prop) == [.goodSport, .onTime])

        let board: PropsLeaderboardResponse = try decode("""
        {"month":"2026-11-01","resets_at":"2026-12-01T06:00:00+00:00",
         "top":[{"rank":1,"id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","first_name":"Lucía","last_initial":"M",
                 "grad_year":2026,"people":21,"mostly":"basketball"}],
         "me":{"opted_in":false,"rank":14,"people":6}}
        """)
        let leaderboard = board.leaderboard
        #expect(leaderboard.top.first?.people == 21)
        #expect(leaderboard.myRank == 14)
        #expect(!leaderboard.isOptedIn)
        #expect(Calendar(identifier: .gregorian).component(.month, from: leaderboard.month) == 11)
    }
}
