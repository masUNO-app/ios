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
    /// One of the signed-in student's unused codes: a waiting account that types it gets in (N37).
    static let inviteCode = "PLAY4NWE"
    /// Their code that Priya already used.
    static let usedInviteCode = "KXPQ7M4D"

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
        /// Unless `-esports NO`: a round night you're in, in its second round.
        static let roundNight = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
        /// One with open spots, in two days.
        static let roundNightOpen = UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!
        /// Yesterday's, for the "who you played with" recap.
        static let roundNightEnded = UUID(uuidString: "00000000-0000-0000-0000-00000000E003")!
        /// Unless `-esports NO`: a plan that ended an hour ago, so props are open.
        static let justEnded = UUID(uuidString: "00000000-0000-0000-0000-00000000A009")!
    }

    enum Places {
        static let basketballCourts = Place(name: MockFixtures.spanishShot("Tec basketball courts", "Canchas de básquet del Tec"), address: "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", latitude: 25.6521, longitude: -100.2903)
        static let stadium = Place(name: "Estadio Borregos", address: "Av. Luis Elizondo, Tecnológico, Monterrey, N.L.", latitude: 25.6489, longitude: -100.2868)
        static let arena = Place(name: "Arena Borregos", address: "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", latitude: 25.6531, longitude: -100.2925)
        static let tennisCourts = Place(name: MockFixtures.spanishShot("Tec tennis courts", "Canchas de tenis del Tec"), address: "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", latitude: 25.6502, longitude: -100.2918)
        static let park = Place(name: "Parque Distrito Tec", address: "Calle Profr. Moisés Sáenz, Tecnológico, Monterrey, N.L.", latitude: 25.6553, longitude: -100.2889)
        static let gameRoom = Place(name: "Tec game room", address: "Centro Estudiantil, Tecnológico, Monterrey, N.L.", latitude: 25.6510, longitude: -100.2899)
        static let sportsCenter = Place(name: "Centro Deportivo Tec", address: "Av. Fernando García Roel, Tecnológico, Monterrey, N.L.", latitude: 25.6475, longitude: -100.2905)
    }

    static func activity(_ slug: String) -> Activity {
        (Activity.builtIn + Activity.esports).first { $0.slug == slug }!
    }

    struct World {
        var me: Profile
        var games: [Game]
        var attendees: [UUID: [Attendee]]
        var people: [UUID: PersonSummary]
        var messages: [UUID: [ChatMessage]]
        var invites: [Invite]
    }

    static func person(_ number: Int, _ first: String, _ initial: String, _ year: Int) -> PersonSummary {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        return PersonSummary(id: id, firstName: first, lastInitial: initial, gradYear: year)
    }

    /// `-screenshots YES`: App Store screenshots (docs/SUBMISSION.md §6). Invented people only (no one
    /// on the team), college game names, afternoon and evening times, and no cancelled game. Off by
    /// default, so tests and design review keep the fixtures they were written against.
    static let isScreenshotWorld = UserDefaults.standard.bool(forKey: "screenshots")

    /// Esports games and round nights (`Rotation`): on since 1.0. `-esports NO` turns them off, which
    /// the tests and screenshots do, so they keep the fixtures they were written against.
    static let isEsportsWorld = UserDefaults.standard.object(forKey: "esports") == nil || UserDefaults.standard.bool(forKey: "esports")

    /// Players for the round nights: invented, enough for 16.
    static let esportsPlayers = [
        ("Lucía", "M"), ("Iker", "S"), ("Renata", "P"), ("Bruno", "A"), ("Fernanda", "O"),
        ("Tomás", "V"), ("Daniela", "R"), ("Andrés", "G"), ("Paola", "N"), ("Héctor", "L"),
        ("Mariana", "T"), ("Emiliano", "C"), ("Sara", "B"), ("Joaquín", "F"), ("Isabela", "D"),
    ].enumerated().map { index, name in person(31 + index, name.0, name.1, 2026 + index % 4) }

    /// The fixture's value, or `shot` under `-screenshots YES`.
    private static func pick<Value>(_ fixture: Value, shot: Value) -> Value {
        isScreenshotWorld ? shot : fixture
    }

    /// The screenshot world in Spanish, for the Spanish listing: the device in Spanish
    /// (`-AppleLanguages "(es-MX)"`) and what students at Tec would write. Ricardo checks the wording.
    static let isSpanishScreenshotWorld = isScreenshotWorld && LanguageSettings.shared.language == "es"

    /// `pick`, with the value for Spanish screenshots.
    private static func pick<Value>(_ fixture: Value, shot: Value, es: Value) -> Value {
        isSpanishScreenshotWorld ? es : pick(fixture, shot: shot)
    }

    /// English text, or its Spanish for Spanish screenshots.
    static func spanishShot(_ english: String, _ spanish: String) -> String {
        isSpanishScreenshotWorld ? spanish : english
    }

    static let alex = pick(person(1, "Alex", "R", 2027), shot: person(1, "Sofía", "R", 2027))
    static let priya = pick(person(2, "Priya", "S", 2028), shot: person(2, "Valeria", "G", 2028))
    static let diego = pick(person(3, "Diego", "M", 2026), shot: person(3, "Diego", "T", 2026))
    static let sam = pick(person(4, "Sam", "L", 2029), shot: person(4, "Mateo", "C", 2029))
    static let maya = pick(person(5, "Maya", "C", 2027), shot: person(5, "Camila", "P", 2027))
    static let ricardo = pick(person(6, "Ricardo", "T", 2027), shot: person(6, "Luis", "H", 2027))
    static let nina = pick(person(7, "Nina", "C", 2028), shot: person(7, "Regina", "S", 2028))
    /// Who's going shows the badge next to these two (N37). Game cards don't carry it, so their
    /// hosted games don't either.
    static let betaTesterIDs: Set<UUID> = [priya.id, sam.id]

    static func world(now: Date, esports: Bool = false) -> World {
        let me = Profile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            firstName: pick("Emilio", shot: "Andrea"), lastName: pick("Garza", shot: "Villarreal"), gradYear: 2029, university: tec,
            interests: [activity("basketball"), activity("soccer"), activity("tennis")],
            chatRulesAcceptedAt: now.addingTimeInterval(-24 * 3600)
        )
        let all = [alex, priya, diego, sam, maya, ricardo, nina]
        var games: [Game] = []
        var attendees: [UUID: [Attendee]] = [:]

        /// `roster[0]` hosts; `minutes` is the start, relative to now.
        func add(
            _ id: UUID, _ title: String, _ slug: String, minutes: Double, duration: Int = 60,
            capacity: Int, roster: [PersonSummary], place: Place, meetPoint: String? = nil,
            notes: String? = nil, cancelled: Bool = false, repostedMinutesAgo: Double? = nil,
            rotation: Rotation? = nil
        ) {
            let duration = rotation?.totalMinutes ?? duration
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
                myJoinedAt: myRole == nil ? nil : joined, hasBlockedAttendee: false, rotation: rotation
            ))
            attendees[id] = roster.enumerated().map { index, person in
                var person = person
                person.isBetaTester = betaTesterIDs.contains(person.id)
                return Attendee(person: person, role: index == 0 ? .host : .player, joinedAt: joined.addingTimeInterval(Double(index) * 60))
            }
        }

        /// Screenshots: minutes from `now` to `hour:minute`, `day` days after a base day (today before
        /// 3 PM, tomorrow after), so games read as afternoon and evening plans whenever they're taken.
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Double {
            let calendar = Calendar.current
            let baseDay = calendar.component(.hour, from: now) < 15 ? 0 : 1
            let midnight = calendar.date(byAdding: .day, value: day + baseDay, to: calendar.startOfDay(for: now))!
            return midnight.addingTimeInterval(Double(hour * 3600 + minute * 60)).timeIntervalSince(now) / 60
        }

        add(GameID.open, pick("After-work hoops", shot: "Pickup after class", es: "Retas después de clase"), "basketball",
            minutes: pick(35, shot: at(0, 17, 30)), capacity: 6, roster: [alex, ricardo],
            place: Places.basketballCourts, meetPoint: spanishShot("Meet by the north court bleachers", "Junto a las gradas de la cancha norte"),
            notes: pick("Casual 3-on-3 after work. Bring a ball if you have one, and some water.",
                        shot: "First time? Come anyway, we rotate every game. Bring water.",
                        es: "¿Primera vez? Vente, rotamos cada juego. Trae agua."))
        add(GameID.lastSpot, pick("Tennis doubles", shot: "Doubles, bring a racket", es: "Dobles, trae raqueta"), "tennis",
            minutes: pick(135, shot: at(0, 19)), capacity: 4, roster: [priya, diego, sam],
            place: Places.tennisCourts, notes: spanishShot("Need one more for doubles. Rackets available.", "Nos falta uno para dobles. Hay raquetas."))
        add(GameID.full, pick("Padel at Distrito Tec", shot: "Padel after class", es: "Pádel después de clase"), "padel",
            minutes: pick(240, shot: at(1, 18)), duration: 90, capacity: 4, roster: [nina, sam, maya, ricardo],
            place: pick(Places.park, shot: Places.sportsCenter))
        add(GameID.going, pick("Volleyball at the arena", shot: "Sunset volleyball", es: "Voleibol al atardecer"), "volleyball",
            minutes: pick(180, shot: at(0, 18, 45)), capacity: 12,
            roster: [sam, nina, maya, priya, me.summary], place: pick(Places.arena, shot: Places.park),
            meetPoint: pick(nil, shot: "Sand court, by the palm trees", es: "Cancha de arena, junto a las palmeras"))
        add(GameID.hosting, pick("Sunday pickup soccer", shot: "Sunday 5v5", es: "Fut 5 del domingo"), "soccer",
            minutes: pick(26 * 60, shot: at(2, 10)), duration: 90, capacity: 10,
            roster: [me.summary, diego, alex], place: Places.stadium, notes: spanishShot("Coming alone is fine.", "Puedes venir solo."))
        add(GameID.ended, pick("Morning hoops", shot: "Shootaround before class", es: "Tiros antes de clase"), "basketball",
            minutes: pick(-26 * 60, shot: at(-1, 7)), capacity: 6, roster: [alex, me.summary, maya],
            place: Places.basketballCourts)
        if !isScreenshotWorld {
            add(GameID.cancelled, "Rainy day soccer", "soccer", minutes: 300, capacity: 10, roster: [diego, sam],
                place: Places.sportsCenter, cancelled: true)
        }
        add(GameID.bumped, pick("Pickup soccer", shot: "Fútbol 7 after class", es: "Fútbol 7 después de clase"), "soccer",
            minutes: pick(50, shot: at(0, 20)), duration: 90, capacity: 10,
            roster: [diego, nina, maya, alex], place: Places.stadium, repostedMinutesAgo: 25)

        if esports {
            let p = esportsPlayers
            // Started 85 minutes ago: round 1 is played and round 2 began 5 minutes ago.
            add(GameID.roundNight, "League night: new squads", "league", minutes: -85, capacity: 16,
                roster: p + [me.summary], place: Places.gameRoom, meetPoint: "Stations are numbered on the screens",
                notes: "Three rounds, new squad each time. PCs are set up, bring your own headset if you like.",
                rotation: .standard)
            add(GameID.roundNightOpen, "CS:GO round robin", "csgo", minutes: 49 * 60, capacity: 16,
                roster: [p[11], p[12], p[13], p[14], alex, diego, nina, p[4], p[5]], place: Places.gameRoom,
                notes: "Four short rounds. First time? Perfect.",
                rotation: Rotation(rounds: 4, roundMinutes: 30, breakMinutes: 10, groupSize: 4))
            add(GameID.roundNightEnded, "Valorant night", "valorant", minutes: -26 * 60, capacity: 10,
                roster: [p[2], me.summary, p[3], p[7], p[8], p[9], p[10], priya, sam, p[1]], place: Places.gameRoom,
                rotation: Rotation(rounds: 2, roundMinutes: 45, breakMinutes: 15, groupSize: 5))
            // Ended an hour ago: props are open (`MockBackend.propsToGive`).
            add(GameID.justEnded, "Sunday 7v7 pickup", "soccer", minutes: -150, duration: 90, capacity: 10,
                roster: [maya, me.summary, alex, diego, nina, sam, priya, ricardo], place: Places.stadium)
        }

        // `-mockGames 150`: copies of the upcoming games you're not in, spread around campus, so pins,
        // groups, filters and search have real work when profiling. Nothing changes without it.
        let extra = UserDefaults.standard.integer(forKey: "mockGames")
        let templates = games.filter { $0.myRole == nil && !$0.isCancelled && $0.startsAt > now }
        for index in 0..<max(extra, 0) where !templates.isEmpty {
            let template = templates[index % templates.count]
            // A sunflower spiral out to about 2 km, so some pins stand alone and some merge.
            let radius = 0.018 * (Double(index + 1) / Double(extra)).squareRoot()
            let angle = Double(index) * 2.39996
            var place = template.place
            place.latitude = tec.centerLatitude + radius * sin(angle)
            place.longitude = tec.centerLongitude + radius * cos(angle)
            add(
                UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index))!,
                "\(template.title) \(index + 2)", template.activity.slug,
                minutes: template.startsAt.timeIntervalSince(now) / 60 + Double(index % 12 * 20),
                duration: template.durationMinutes, capacity: template.capacity,
                roster: attendees[template.id]?.map(\.person) ?? [template.host], place: place
            )
        }

        var messages: [UUID: [ChatMessage]] = [:]
        func say(_ gameID: UUID, _ sender: PersonSummary, _ body: String, minutesAgo: Double, mentions: [UUID] = []) {
            messages[gameID, default: []].append(ChatMessage(
                id: UUID(), gameID: gameID, sender: sender, body: body, clientID: UUID(),
                createdAt: now.addingTimeInterval(-minutesAgo * 60), mentions: mentions
            ))
        }
        say(GameID.going, sam, pick("Net's up on the far court. Bring water, it's hot in there.",
                                    shot: "Net's up on the sand court. Bring water 🏐",
                                    es: "Ya está la red en la cancha de arena. Traigan agua 🏐"), minutesAgo: 95)
        say(GameID.going, maya, spanishShot("I can bring a second ball", "Yo llevo otro balón"), minutesAgo: 90)
        say(GameID.going, me.summary, spanishShot("Perfect. First time playing with you all, see you there!",
                                                  "Perfecto. Es mi primera vez jugando con ustedes, ¡nos vemos!"), minutesAgo: 42)
        // A mention of you, highlighted in the chat (NOTIF §3.5).
        say(GameID.going, sam, spanishShot("Welcome \(Mention.token(for: me.summary))! We start with a quick warm-up at 10 to.",
                                           "¡Bienvenida, \(Mention.token(for: me.summary))! Calentamos 10 minutos antes."),
            minutesAgo: 40, mentions: [me.id])
        say(GameID.hosting, diego, spanishShot("Should we bring bibs?", "¿Llevamos petos?"), minutesAgo: 120)
        say(GameID.hosting, me.summary, spanishShot("I have a set, don't worry.", "Yo tengo, no te preocupes."), minutesAgo: 110)

        // Three codes, oldest first, like `my_invites`: one Priya used, two still open.
        let invites = [
            Invite(code: usedInviteCode, createdAt: now.addingTimeInterval(-9 * 24 * 3600),
                   redeemedAt: now.addingTimeInterval(-2 * 24 * 3600), redeemedBy: priya.displayName),
            Invite(code: inviteCode, createdAt: now.addingTimeInterval(-9 * 24 * 3600)),
            Invite(code: "JUMP3ZRS", createdAt: now.addingTimeInterval(-9 * 24 * 3600)),
        ]

        if esports {
            say(GameID.roundNight, esportsPlayers[0], "Round 2 groups are up! Check your station number.", minutesAgo: 6)
        }

        let people = Dictionary(uniqueKeysWithValues: (all + (esports ? esportsPlayers : [])).map { ($0.id, $0) })
        return World(me: me, games: games, attendees: attendees, people: people, messages: messages, invites: invites)
    }
}
#endif
