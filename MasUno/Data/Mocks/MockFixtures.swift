#if DEBUG
import Foundation

/// Monterrey mock data: one game in each Event detail state, with times relative to `now`.
/// Places are approximate placeholders until Ricardo's venue list (O5).
enum MockFixtures {
    static let tec = University(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!,
        name: "Tec de Monterrey", shortName: "Tec", emailDomain: "tec.mx",
        centerLatitude: 25.6514, centerLongitude: -100.2895, ssoProvider: .azure
    )
    /// Any other campus, to prove nothing is tied to Tec.
    static let otherCampus = University(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!,
        name: "UANL", shortName: "UANL", emailDomain: "uanl.edu.mx",
        centerLatitude: 25.7260, centerLongitude: -100.3120, ssoProvider: .google
    )
    /// Hidden App Review campus (C12): not listed as open, but review accounts land here.
    static let demoCampus = University(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!,
        name: "masUNO Demo", shortName: "Demo", emailDomain: "demo.masuno.invalid",
        centerLatitude: 25.6600, centerLongitude: -100.3000
    )
    static let reviewEmail = "official.masuno.app+review1@gmail.com"
    static let reviewPassword = "review-password"

    /// Fixed so previews and tests can refer to a game by state.
    enum GameID {
        static let open = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
        static let lastSpot = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
        static let full = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!
        static let going = UUID(uuidString: "00000000-0000-0000-0000-00000000A004")!
        static let hosting = UUID(uuidString: "00000000-0000-0000-0000-00000000A005")!
        static let ended = UUID(uuidString: "00000000-0000-0000-0000-00000000A006")!
        static let cancelled = UUID(uuidString: "00000000-0000-0000-0000-00000000A007")!
        static let bumped = UUID(uuidString: "00000000-0000-0000-0000-00000000A008")!
    }

    enum Places {
        static let basketballCourts = Place(name: "Tec basketball courts", address: "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", latitude: 25.6521, longitude: -100.2903)
        static let stadium = Place(name: "Estadio Borregos", address: "Av. Luis Elizondo, Tecnológico, Monterrey, N.L.", latitude: 25.6489, longitude: -100.2868)
        static let arena = Place(name: "Arena Borregos", address: "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", latitude: 25.6531, longitude: -100.2925)
        static let tennisCourts = Place(name: "Tec tennis courts", address: "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", latitude: 25.6502, longitude: -100.2918)
        static let park = Place(name: "Parque Distrito Tec", address: "Calle Profr. Moisés Sáenz, Tecnológico, Monterrey, N.L.", latitude: 25.6553, longitude: -100.2889)
        static let sportsCenter = Place(name: "Centro Deportivo Tec", address: "Av. Fernando García Roel, Tecnológico, Monterrey, N.L.", latitude: 25.6475, longitude: -100.2905)
    }

    static func activity(_ slug: String) -> Activity {
        Activity.builtIn.first { $0.slug == slug }!
    }

    struct World {
        var me: Profile
        var games: [Game]
        var attendees: [UUID: [Attendee]]
        var people: [UUID: PersonSummary]
    }

    static func person(_ number: Int, _ first: String, _ initial: String, _ year: Int) -> PersonSummary {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        return PersonSummary(id: id, firstName: first, lastInitial: initial, gradYear: year)
    }

    static let alex = person(1, "Alex", "R", 2027)
    static let priya = person(2, "Priya", "S", 2028)
    static let diego = person(3, "Diego", "M", 2026)
    static let sam = person(4, "Sam", "L", 2029)
    static let maya = person(5, "Maya", "C", 2027)
    static let ricardo = person(6, "Ricardo", "T", 2027)
    static let nina = person(7, "Nina", "C", 2028)

    static func world(now: Date) -> World {
        let me = Profile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            firstName: "Emilio", lastName: "Garza", gradYear: 2029, university: tec,
            interests: [activity("basketball"), activity("soccer"), activity("tennis")]
        )
        let all = [alex, priya, diego, sam, maya, ricardo, nina]
        var games: [Game] = []
        var attendees: [UUID: [Attendee]] = [:]

        /// `roster[0]` hosts; `minutes` is the start, relative to now.
        func add(
            _ id: UUID, _ title: String, _ slug: String, minutes: Double, duration: Int = 60,
            capacity: Int, roster: [PersonSummary], place: Place, meetPoint: String? = nil,
            notes: String? = nil, cancelled: Bool = false, repostedMinutesAgo: Double? = nil
        ) {
            let start = now.addingTimeInterval(minutes * 60)
            let host = roster[0]
            let joined = now.addingTimeInterval(-3 * 3600)
            let myRole: GameRole? = host.id == me.id ? .host : roster.contains { $0.id == me.id } ? .player : nil
            games.append(Game(
                id: id, host: host, activity: activity(slug), title: title,
                startsAt: start, durationMinutes: duration,
                endsAt: start.addingTimeInterval(Double(duration) * 60),
                capacity: capacity, goingCount: roster.count, notes: notes, place: place,
                meetPoint: meetPoint, cancelledAt: cancelled ? now.addingTimeInterval(-600) : nil,
                autoRepost: true, repostedAt: repostedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
                createdAt: now.addingTimeInterval(-6 * 3600), myRole: myRole,
                myJoinedAt: myRole == nil ? nil : joined, hasBlockedAttendee: false
            ))
            attendees[id] = roster.enumerated().map { index, person in
                Attendee(person: person, role: index == 0 ? .host : .player, joinedAt: joined.addingTimeInterval(Double(index) * 60))
            }
        }

        add(GameID.open, "After-work hoops", "basketball", minutes: 35, capacity: 6, roster: [alex, ricardo],
            place: Places.basketballCourts, meetPoint: "Meet by the north court bleachers",
            notes: "Casual 3-on-3 after work. Bring a ball if you have one, and some water.")
        add(GameID.lastSpot, "Tennis doubles", "tennis", minutes: 135, capacity: 4, roster: [priya, diego, sam],
            place: Places.tennisCourts, notes: "Need one more for doubles. Rackets available.")
        add(GameID.full, "Padel at Distrito Tec", "padel", minutes: 240, duration: 90, capacity: 4, roster: [nina, sam, maya, ricardo],
            place: Places.park)
        add(GameID.going, "Volleyball at the arena", "volleyball", minutes: 180, capacity: 12,
            roster: [sam, nina, maya, priya, me.summary], place: Places.arena)
        add(GameID.hosting, "Sunday pickup soccer", "soccer", minutes: 26 * 60, duration: 90, capacity: 10,
            roster: [me.summary, diego, alex], place: Places.stadium, notes: "Coming alone is fine.")
        add(GameID.ended, "Morning hoops", "basketball", minutes: -26 * 60, capacity: 6, roster: [alex, me.summary, maya],
            place: Places.basketballCourts)
        add(GameID.cancelled, "Rainy day soccer", "soccer", minutes: 300, capacity: 10, roster: [diego, sam],
            place: Places.sportsCenter, cancelled: true)
        add(GameID.bumped, "Pickup soccer", "soccer", minutes: 50, duration: 90, capacity: 10,
            roster: [diego, nina, maya, alex], place: Places.stadium, repostedMinutesAgo: 25)

        let people = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return World(me: me, games: games, attendees: attendees, people: people)
    }
}
#endif
