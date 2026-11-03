import CoreLocation
import Foundation
import MapKit

/// Mock content mirroring the green Figma frames, moved to Tec's Monterrey campus.
/// Times are relative to launch so "starts in" labels always look live.
/// Venue names and coordinates are approximate placeholders until Ricardo's venue list (O5).
enum MockData {
    /// Tec campus center (SPEC §7.6.1).
    static let campusCenter = CLLocationCoordinate2D(latitude: 25.6514, longitude: -100.2895)
    static let userLocation = CLLocationCoordinate2D(latitude: 25.6533, longitude: -100.2872)

    static let campusRegion = MKCoordinateRegion(
        center: campusCenter,
        span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)
    )

    enum Venues {
        static let city = "Tecnológico, Monterrey, N.L."

        static let basketballCourts = Venue(name: "Tec basketball courts", street: "Av. Eugenio Garza Sada 2501 Sur", city: city, latitude: 25.6521, longitude: -100.2903)
        static let borregosStadium = Venue(name: "Estadio Borregos", street: "Av. Luis Elizondo", city: city, latitude: 25.6489, longitude: -100.2868)
        static let arena = Venue(name: "Arena Borregos", street: "Av. Junco de la Vega", city: city, latitude: 25.6531, longitude: -100.2925)
        static let tennisCourts = Venue(name: "Tec tennis courts", street: "Av. Eugenio Garza Sada 2501 Sur", city: city, latitude: 25.6502, longitude: -100.2918)
        static let distritoTec = Venue(name: "Parque Distrito Tec", street: "Calle Profr. Moisés Sáenz", city: city, latitude: 25.6553, longitude: -100.2889)
        static let sportsCenter = Venue(name: "Centro Deportivo Tec", street: "Av. Fernando García Roel", city: city, latitude: 25.6475, longitude: -100.2905)

        static let all = [basketballCourts, borregosStadium, arena, tennisCourts, distritoTec, sportsCenter]
    }

    /// Your profile on the Me card. Replaced by the signed-in profile once auth lands (B5).
    static let profile = Profile(
        firstName: "Emilio", lastName: "Garza", classYear: 2029,
        school: "Tec de Monterrey", isVerified: true,
        interests: [.basketball, .soccer, .tennis]
    )

    static func events(now: Date = .now) -> [SportsEvent] {
        func inMinutes(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let calendar = Calendar.current
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        return [
            // MARK: Map
            SportsEvent(
                // Popup + Event detail frames.
                title: "After-work hoops", sport: .basketball, host: "Alex Rivera",
                start: inMinutes(35), duration: 3600, capacity: 6,
                attendees: ["Alex Rivera", "Ricardo Treviño"], venue: Venues.basketballCourts,
                meetUpSpot: "Meet by the north court bleachers",
                notes: "Casual 3-on-3 after work. Bring a ball if you have one, and some water. We'll play for about an hour."
            ),
            SportsEvent(
                title: "Tennis doubles", sport: .tennis, host: "Priya Shah",
                start: inMinutes(135), duration: 3600, capacity: 4,
                attendees: ["Priya Shah", "Ben Ortiz"], venue: Venues.tennisCourts,
                notes: "Need two more for doubles. Rackets available."
            ),
            SportsEvent(
                title: "Pickup soccer", sport: .soccer, host: "Diego Morales",
                start: inMinutes(50), duration: 5400, capacity: 10,
                attendees: ["Diego Morales", "Sam Lee", "Nina Cruz", "Jules Park", "Leo Park", "Maya Chen", "Ben Ortiz"],
                venue: Venues.borregosStadium
            ),
            SportsEvent(
                title: "Volleyball at the arena", sport: .volleyball, host: "Sam Lee",
                start: inMinutes(180), duration: 3600, capacity: 12,
                attendees: ["Sam Lee", "Nina Cruz", "Jules Park", "Leo Park", "Maya Chen", "Priya Shah", "Diego Morales"],
                venue: Venues.arena
            ),
            SportsEvent(
                title: "3v3 at Distrito Tec", sport: .basketball, host: "Ricardo Treviño",
                start: inMinutes(300), duration: 3600, capacity: 6,
                attendees: ["Ricardo Treviño", "Leo Park", "Diego Morales", "Sam Lee", "Ben Ortiz"],
                venue: Venues.distritoTec, notes: "One more and we're set."
            ),
            // Full: hidden from the map.
            SportsEvent(
                title: "Friday night 5v5", sport: .basketball, host: "Jules Park",
                start: day(1, 19), duration: 5400, capacity: 10,
                attendees: ["Jules Park", "Alex Rivera", "Ben Ortiz", "Diego Morales", "Leo Park", "Maya Chen", "Nina Cruz", "Priya Shah", "Ricardo Treviño", "Sam Lee"],
                venue: Venues.sportsCenter
            ),

            // MARK: Me · Going
            SportsEvent(
                title: "Sunday soccer", sport: .soccer, host: "Maya Chen",
                start: day(1, 10), duration: 5400, capacity: 10,
                attendees: ["Maya Chen", "Leo Park", Person.you, "Sofía Ramírez", "Diego Morales"],
                venue: Venues.borregosStadium, meetUpSpot: "By the south goal",
                notes: "Friendly 5-a-side. Bring a light and a dark shirt."
            ),
            SportsEvent(
                title: "Saturday tennis", sport: .tennis, host: "Jordan Lee",
                start: day(2, 18, 30), duration: 5400, capacity: 4,
                attendees: ["Jordan Lee", Person.you, "Sofía Ramírez", "Ben Ortiz"], venue: Venues.tennisCourts
            ),
            // Ended and cancelled games you were going to (Event detail states).
            SportsEvent(
                title: "Morning shootaround", sport: .basketball, host: "Alex Rivera",
                start: day(-1, 8), duration: 3600, capacity: 6,
                attendees: ["Alex Rivera", Person.you, "Leo Park"], venue: Venues.basketballCourts
            ),
            SportsEvent(
                title: "Beach volleyball", sport: .volleyball, host: "Sofía Ramírez",
                start: day(1, 17), duration: 3600, capacity: 8,
                attendees: ["Sofía Ramírez", Person.you, "Nina Cruz"], venue: Venues.arena,
                isCancelled: true
            ),

            // MARK: Me · Hosting
            SportsEvent(
                title: "Sunday hoops", sport: .basketball, host: Person.you,
                start: day(1, 10), duration: 3600, capacity: 6,
                attendees: [Person.you, "Maya Chen", "Leo Park"], venue: Venues.basketballCourts,
                meetUpSpot: "South court, by the water fountain",
                notes: "Run 3-on-3, winners stay on."
            ),
            SportsEvent(
                title: "Volleyball night", sport: .volleyball, host: Person.you,
                start: day(2, 18, 30), duration: 7200, capacity: 6,
                attendees: [Person.you, "Alex Rivera", "Priya Shah", "Ben Ortiz"], venue: Venues.sportsCenter
            ),
        ]
    }
}
