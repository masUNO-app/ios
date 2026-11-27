import CoreLocation
import Foundation

/// Which half of the practice round (Figma "Onboarding, reimagined", 0R): taking the open spot in
/// someone's plan, or making your own.
nonisolated enum PracticeMode: Hashable, Sendable {
    case join, host
}

/// The plan made in the practice round. Nothing is posted: "Keep this plan" keeps it, and once
/// the account is in, Make a plan opens with it filled in (`GameFormSheet(practice:)`).
nonisolated struct PracticePlan: Hashable, Sendable {
    var activity: Activity
    var title: String
    var capacity: Int
    var notes: String
}

/// The pretend plans and people of the practice round and the Welcome carousel. Nothing here is
/// real or sent anywhere; the copy says so ("This was a practice plan…").
enum PracticeRound {
    /// The people on the Welcome courts and in the practice plans. The same person keeps the same
    /// ID, so they walk to their new spot as the carousel changes sport. The last byte picks the
    /// palette color (`AvatarPalette.index`), matching the Figma: Alex yellow, Ricardo purple…
    static let alex = person(1, "Alex", "R")
    static let ricardo = person(6, "Ricardo", "T")
    static let priya = person(2, "Priya", "S")
    static let ben = person(12, "Ben", "O")
    static let diego = person(3, "Diego", "M")
    static let sam = person(4, "Sam", "L")
    static let nina = person(7, "Nina", "C")
    static let jules = person(19, "Jules", "P")
    static let leo = person(13, "Leo", "P")
    static let maya = person(9, "Maya", "C")
    static let sofia = person(10, "Sofía", "R")
    /// You, in the practice: no name yet, so tokens show "You".
    static let you = person(99, "", "")

    static func person(_ number: UInt8, _ first: String, _ initial: String) -> PersonSummary {
        PersonSummary(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number)), firstName: first, lastInitial: initial, gradYear: 0)
    }

    // MARK: Welcome carousel

    /// The built-in sports, for the practice map's other pins.
    static var welcomeSports: [Activity] { Activity.builtIn.sorted { $0.sortOrder < $1.sortOrder } }

    /// The courts Welcome cycles through, as on the website's hero: every active activity in the
    /// server's catalog, which serves esports to 1.0 and later (`activity_catalog`). Before the
    /// catalog loads, the built-in sports.
    static func welcomeSports(from catalog: [Activity]) -> [Activity] {
        let active = catalog.filter(\.active).sorted { $0.sortOrder < $1.sortOrder }
        return active.isEmpty ? welcomeSports : active
    }

    /// Who's already on each Welcome court, and how many spots it has. One open spot is the one
    /// you can take ("Be the +1").
    static func welcomeCourt(for sport: Activity) -> (people: [PersonSummary], capacity: Int) {
        switch sport.slug {
        case "basketball": ([alex, ricardo], 6)
        case "tennis": ([priya, ben], 4)
        case "soccer": ([diego, sam, nina, jules, leo, maya, ben], 10)
        case "volleyball": ([sam, nina, jules, leo, maya, priya, diego], 11)
        case "padel": ([sofia, nina, ben], 4)
        // A 5-stack around the screen, as on the website: four in, one to go.
        case _ where sport.isEsport: ([ricardo, maya, sofia, diego], 5)
        default: ([alex, ricardo], 6)
        }
    }

    /// The speech bubble over each Welcome court; the website's lines.
    static func welcomeCall(for sport: Activity) -> String {
        switch sport.slug {
        case "basketball": String.app("Need 1 more for 3v3")
        case "tennis": String.app("Need one more for doubles!")
        case "soccer": String.app("Need 1 more for 5-a-side")
        case "volleyball": String.app("One more and we can start")
        case "padel": String.app("Need a fourth for padel")
        case "valorant": String.app("Need a fifth for Valorant")
        case "csgo": String.app("One more for a 5-stack")
        case "league": String.app("Need a support for League")
        // An activity added on the server after this build.
        default: String.app("Need one more for \(sport.name)")
        }
    }

    // MARK: Practice plans

    /// How many people a practice plan has room for, including the host.
    static func capacity(for sport: Activity) -> Int {
        switch sport.slug {
        case "tennis", "padel": 4
        case "soccer": 10
        case "volleyball": 12
        default: sport.isEsport ? 5 : 6
        }
    }

    /// What Make a plan fills in for you in the practice ("We filled in the basics").
    static func suggestedPlan(for sport: Activity) -> PracticePlan {
        let (title, notes): (String, String) = switch sport.slug {
        case "basketball": (String.app("After-work hoops"), String.app("Casual 3-on-3. I have an extra ball."))
        case "tennis": (String.app("Doubles after class"), String.app("All levels. I'll bring balls."))
        case "soccer": (String.app("5-a-side kickabout"), String.app("Ball and bibs covered. Just show up."))
        case "volleyball": (String.app("Sunset volleyball"), String.app("Casual games, everyone rotates in."))
        case "padel": (String.app("Padel, need a fourth"), String.app("Spare racket if you need one."))
        default: (String.app("\(sport.name) night"), String.app("Chill games, all levels welcome."))
        }
        return PracticePlan(activity: sport, title: title, capacity: capacity(for: sport), notes: notes)
    }

    /// The plan whose open spot you take in the practice: Alex's, with Ricardo already in, starting
    /// in about 35 minutes.
    static func joinPlan(for sport: Activity, campus: University?, now: Date = .now) -> Game {
        let start = roundedUp(now.addingTimeInterval(35 * 60), toMinutes: 5)
        return game(
            id: 1, host: alex, activity: sport, title: suggestedPlan(for: sport).title,
            startsAt: start, capacity: capacity(for: sport), going: 2,
            place: place(for: sport, campus: campus), myRole: nil
        )
    }

    /// Your plan once Create plan is tapped: you and the open spots, this evening.
    static func hostedPlan(_ plan: PracticePlan, campus: University?, now: Date = .now) -> Game {
        game(
            id: 2, host: you, activity: plan.activity, title: plan.title,
            startsAt: hostedStart(now: now), capacity: plan.capacity, going: 1,
            place: place(for: plan.activity, campus: campus), myRole: .host
        )
    }

    /// A pin on the practice map: a pretend plan and the faces under it.
    struct Pin: Identifiable {
        var plan: Game
        var people: [PersonSummary]
        var id: UUID { plan.id }
    }

    /// Who's in the plan you join: Alex hosts, Ricardo's in.
    static let joinPeople = [alex, ricardo]

    /// The other pins on the practice map: the sports you didn't pick for the practice, with a few
    /// people under each.
    static func otherPins(besides sport: Activity, now: Date = .now) -> [Pin] {
        let crowds: [String: [PersonSummary]] = [
            "basketball": [alex, ricardo],
            "tennis": [priya, ben],
            "soccer": [diego, jules, ben],
            "volleyball": [maya, nina],
            "padel": [sofia, nina],
        ]
        return welcomeSports.filter { $0.slug != sport.slug }.prefix(4).enumerated().map { index, other in
            let people = crowds[other.slug] ?? [alex]
            // Every other one starts within the hour, so its pin says "Soon", as on the real map.
            let start = now.addingTimeInterval(index.isMultiple(of: 2) ? 3 * 3600 : 40 * 60)
            let plan = game(
                id: UInt8(10 + index), host: people[0], activity: other, title: suggestedPlan(for: other).title,
                startsAt: start, capacity: capacity(for: other), going: people.count,
                place: place(for: other, campus: nil), myRole: nil
            )
            return Pin(plan: plan, people: people)
        }
    }

    /// "Today at 7:30 PM" for a plan made now: half past five or half past seven, whichever is at
    /// least an hour away; past that, tomorrow at half past five (never a plan at midnight).
    static func hostedStart(now: Date) -> Date {
        let calendar = Calendar.current
        for hour in [17, 19] {
            if let slot = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: now), slot.timeIntervalSince(now) >= 3600 {
                return slot
            }
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 3600)
        return calendar.date(bySettingHour: 17, minute: 30, second: 0, of: tomorrow) ?? roundedUp(now.addingTimeInterval(90 * 60), toMinutes: 30)
    }

    private static func roundedUp(_ date: Date, toMinutes step: Int) -> Date {
        let seconds = Double(step * 60)
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / seconds).rounded(.up) * seconds)
    }

    /// "Tec basketball courts", or "Campus basketball courts" before a campus is known.
    static func place(for sport: Activity, campus: University?) -> Place {
        let campusName = campus?.shortName ?? String.app("Campus")
        let name = switch sport.slug {
        case "basketball": String.app("\(campusName) basketball courts")
        case "tennis": String.app("\(campusName) tennis courts")
        case "soccer": String.app("\(campusName) soccer field")
        case "volleyball": String.app("\(campusName) volleyball courts")
        case "padel": String.app("\(campusName) padel courts")
        case _ where sport.isEsport: String.app("\(campusName) game room")
        default: String.app("\(campusName) student center")
        }
        let center = campus?.center ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return Place(name: name, address: name, latitude: center.latitude, longitude: center.longitude)
    }

    private static func game(
        id: UInt8, host: PersonSummary, activity: Activity, title: String, startsAt: Date,
        capacity: Int, going: Int, place: Place, myRole: GameRole?
    ) -> Game {
        let duration = 60
        return Game(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xAA, id)),
            host: host, activity: activity, title: title, startsAt: startsAt, durationMinutes: duration,
            endsAt: startsAt.addingTimeInterval(Double(duration) * 60), capacity: capacity, goingCount: going,
            notes: nil, place: place, meetPoint: nil, materialChangeAt: nil, cancelledAt: nil,
            autoRepost: false, repostedAt: nil, createdAt: startsAt, myRole: myRole, myJoinedAt: nil,
            hasBlockedAttendee: false
        )
    }
}
