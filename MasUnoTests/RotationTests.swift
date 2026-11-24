import Foundation
import Testing
@testable import masUNO

/// Esports and round nights (`-esports YES`): the planner, the mock's rules and the form.
@MainActor
struct RotationTests {
    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 500 + $0))! }
    }

    /// Pairs that played together in more than one round.
    private func repeatPairs(_ rounds: [[[UUID]]]) -> Int {
        var seen: [Set<UUID>: Int] = [:]
        for group in rounds.joined() {
            for a in group { for b in group where a.uuidString < b.uuidString { seen[[a, b], default: 0] += 1 } }
        }
        return seen.values.filter { $0 > 1 }.count
    }

    private func plan(_ people: [UUID], size: Int, rounds: Int, game: UUID = UUID()) -> [[[UUID]]] {
        var locked: [[[UUID]]] = []
        for round in 0..<rounds {
            locked.append(RotationPlanner.groups(of: people, size: size, earlier: locked, seed: RotationPlanner.seed(game: game, round: round)))
        }
        return locked
    }

    // MARK: Planner

    @Test func sixteenPlayersMeetNineNewPeopleWithNoRepeats() {
        let people = ids(16)
        let rounds = plan(people, size: 4, rounds: 3)
        for round in rounds {
            #expect(round.map(\.count) == [4, 4, 4, 4])
            #expect(Set(round.joined()) == Set(people))
        }
        #expect(repeatPairs(rounds) == 0)
    }

    @Test func leftoversJoinGroupsOneEach() {
        let groups = RotationPlanner.groups(of: ids(10), size: 4, earlier: [], seed: 7)
        #expect(groups.map(\.count).sorted() == [5, 5])
        #expect(RotationPlanner.groups(of: ids(3), size: 4, earlier: [], seed: 7).map(\.count) == [3])
        #expect(RotationPlanner.groups(of: [], size: 4, earlier: [], seed: 7).isEmpty)
    }

    @Test func sameSeedSameGroups() {
        let game = UUID()
        #expect(plan(ids(12), size: 3, rounds: 3, game: game) == plan(ids(12), size: 3, rounds: 3, game: game))
    }

    @Test func timesFollowRoundsAndBreaks() {
        let start = Date(timeIntervalSince1970: 0)
        let rotation = Rotation.standard
        #expect(rotation.totalMinutes == 220)
        #expect(rotation.start(of: 1, from: start).timeIntervalSince(start) == 80 * 60)
        #expect(rotation.end(of: 2, from: start).timeIntervalSince(start) == 220 * 60)
        #expect(rotation.reveal(of: 0, from: start) == start)
        #expect(rotation.reveal(of: 1, from: start) == rotation.end(of: 0, from: start))
        #expect(rotation.mostNewPeople(players: 16) == 9)
        #expect(rotation.mostNewPeople(players: 6) == 5)
    }

    // MARK: Mock backend

    @Test func noEsportsWithoutTheFlag() async throws {
        let backend = MockBackend(esports: false)
        #expect(try await backend.fetchActivities().allSatisfy { !$0.isEsport })
        #expect(try await backend.fetchMyGames().allSatisfy { $0.rotation == nil })
    }

    @Test func roundNightInProgressShowsPlayedAndCurrentGroups() async throws {
        let backend = MockBackend(esports: true)
        let plan = try await backend.fetchRotation(gameID: MockFixtures.GameID.roundNight)
        #expect(plan.rounds.count == 3)
        #expect(plan.rounds.map { $0.groups != nil } == [true, true, false])
        for round in plan.rounds.prefix(2) {
            let everyone = round.groups!.joined().map(\.id)
            #expect(everyone.count == 16)
            #expect(Set(everyone).count == 16)
            #expect(plan.group(of: backend.me.id, in: round)?.people.count == 3)
        }
        #expect(plan.peopleMet(by: backend.me.id).count == 6)
    }

    @Test func revealedGroupsStayPutWhenPeopleJoinLater() async throws {
        let backend = MockBackend(esports: true)
        let id = MockFixtures.GameID.roundNightOpen
        let game = try await backend.fetchGame(id: id)
        _ = try await backend.joinGame(id: id)

        #expect(try await backend.fetchRotation(gameID: id).rounds.allSatisfy { $0.groups == nil })
        backend.now = game.startsAt.addingTimeInterval(60)
        let first = try await backend.fetchRotation(gameID: id).rounds[0].groups
        #expect(first != nil)

        backend.fillGameWithPlayers(id: id)
        let after = try await backend.fetchRotation(gameID: id)
        #expect(after.rounds[0].groups == first)
        #expect(after.rounds[1].groups == nil)

        backend.now = game.startsAt.addingTimeInterval(Double(game.rotation!.roundMinutes) * 60)
        let second = try await backend.fetchRotation(gameID: id).rounds[1].groups
        #expect(second?.joined().count == (try await backend.fetchAttendees(gameID: id)).count)
    }

    @Test func plainGamesHaveNoRotation() async throws {
        let backend = MockBackend(esports: true)
        await #expect(throws: DomainError.notFound) {
            try await backend.fetchRotation(gameID: MockFixtures.GameID.open)
        }
    }

    @Test func createChecksRoundNights() async throws {
        let backend = MockBackend(esports: true)
        let league = try #require(Activity.esports.first { $0.slug == "league" })
        var draft = GameDraft(
            activity: league, title: "League night", startsAt: backend.now.addingTimeInterval(3600),
            durationMinutes: Rotation.standard.totalMinutes, capacity: 16, place: MockFixtures.Places.gameRoom,
            rotation: .standard
        )

        var sport = draft
        sport.activity = MockFixtures.activity("basketball")
        await #expect(throws: DomainError.invalidInput) { try await backend.createGame(sport) }
        var wrongLength = draft
        wrongLength.durationMinutes = 60
        await #expect(throws: DomainError.invalidInput) { try await backend.createGame(wrongLength) }
        var tooFew = draft
        tooFew.capacity = 7
        await #expect(throws: DomainError.invalidInput) { try await backend.createGame(tooFew) }

        let game = try await backend.createGame(draft)
        #expect(game.rotation == .standard)
        #expect(game.endsAt.timeIntervalSince(game.startsAt) == 220 * 60)

        draft.rotation = nil
        draft.durationMinutes = 60
        #expect(try await backend.createGame(draft).rotation == nil)
    }

    // MARK: Form

    @Test func formCreatesARoundNight() async throws {
        let backend = MockBackend(esports: true)
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "RotationTests.\(UUID().uuidString)")!
        )
        await store.load()
        #expect(store.activityKinds.map(\.slug) == [Activity.sportKind, Activity.esportsKind])

        let form = GameFormViewModel()
        form.setKind(Activity.esportsKind, from: store.postableActivities)
        #expect(form.supportsRotation)
        #expect(form.saveButtonTitle == "Create plan")
        form.rotates = true
        #expect(form.players == 16)
        #expect(form.playersHint == "4 groups of 4")
        #expect(form.saveButtonTitle == "Create round night")
        form.players = 7
        #expect(form.playersHint == "Room for 2 groups needed")
        form.players = 10
        #expect(form.playersHint == "2 groups of 4–5")

        form.name = "Valorant night"
        form.place = MockFixtures.Places.gameRoom
        form.day = form.dayOptions[1]
        form.time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now)!
        #expect(await form.save(in: store))
        let created = try #require(store.lastCreatedID.flatMap(store.game))
        #expect(created.rotation == .standard)
        #expect(created.durationMinutes == 220)

        // Back to sports: an ordinary game, the rounds kept for switching back.
        let sports = GameFormViewModel()
        sports.setKind(Activity.esportsKind, from: store.postableActivities)
        sports.rotates = true
        sports.setKind(Activity.sportKind, from: store.postableActivities)
        #expect(!sports.usesRotation)
        #expect(sports.effectiveDuration == 60)
    }

    @Test func roundNightNeedsTwoGroups() {
        let form = GameFormViewModel()
        form.sport = Activity.esports[0]
        form.rotates = true
        form.players = 6
        form.showsErrors = true
        #expect(form.rotationError != nil)
        #expect(form.error(for: .rotation) != nil)
        form.players = 8
        #expect(form.rotationError == nil)
    }
}
