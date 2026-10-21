import CoreLocation
import Foundation
import MapKit

/// Mock content mirroring the Figma frames. Times are relative to launch so
/// the map's "starts in" labels always look live.
enum MockData {
    static let userLocation = CLLocationCoordinate2D(latitude: 37.7880, longitude: -122.4028)

    static let initialRegion = MKCoordinateRegion(
        center: .init(latitude: 37.7853, longitude: -122.4058),
        span: .init(latitudeDelta: 0.011, longitudeDelta: 0.011)
    )

    enum Venues {
        static let unionSquare = Venue(name: "Union Square Courts", street: "333 Post St", city: "San Francisco, CA 94108", latitude: 37.7881, longitude: -122.4078)
        static let yerbaBuena = Venue(name: "Yerba Buena Gardens", street: "750 Howard St", city: "San Francisco, CA 94103", latitude: 37.7858, longitude: -122.4044)
        static let market760 = Venue(name: "760 Market Street", street: "760 Market Street", city: "San Francisco, CA 94107", latitude: 37.7856, longitude: -122.4071)
        static let fourthAndMarket = Venue(name: "4th & Market Plaza", street: "4th St & Market St", city: "San Francisco, CA 94103", latitude: 37.7830, longitude: -122.4040)
        static let mintPlaza = Venue(name: "Mint Plaza", street: "1 Mint Plaza", city: "San Francisco, CA 94103", latitude: 37.7823, longitude: -122.4085)
        static let moscone = Venue(name: "Moscone Recreation Center", street: "1800 Chestnut St", city: "San Francisco, CA 94123", latitude: 37.8007, longitude: -122.4345)
        static let missionRec = Venue(name: "Mission Rec Center", street: "2450 Harrison St", city: "San Francisco, CA 94110", latitude: 37.7590, longitude: -122.4125)
        static let doloresPark = Venue(name: "Dolores Park", street: "19th & Dolores St", city: "San Francisco, CA 94114", latitude: 37.7596, longitude: -122.4269)
        static let ritualCoffee = Venue(name: "Ritual Coffee", street: "1026 Valencia St", city: "San Francisco, CA 94110", latitude: 37.7565, longitude: -122.4213)
        static let kezar = Venue(name: "Kezar Pavilion", street: "755 Stanyan St", city: "San Francisco, CA 94117", latitude: 37.7671, longitude: -122.4547)

        /// Choices in the Add event sheet.
        static let postable = [moscone, unionSquare, yerbaBuena, mintPlaza, missionRec, market760]
    }

    static func events(now: Date = .now) -> [SportsEvent] {
        func inMinutes(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let calendar = Calendar.current
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func msg(_ sender: String, _ text: String, minutesAgo: Double) -> ChatMessage {
            ChatMessage(sender: sender, text: text, sentAt: now.addingTimeInterval(-minutesAgo * 60))
        }

        return [
            // MARK: Map (Sports event map frame)
            SportsEvent(
                title: "Tennis Doubles", sport: .tennis, host: "Priya",
                start: inMinutes(135), duration: 3600, capacity: 4,
                attendees: ["Priya", "Ben"], venue: Venues.unionSquare,
                skillLevel: .casual, notes: "Need two more for doubles. Rackets available."
            ),
            SportsEvent(
                title: "Pickup Soccer", sport: .soccer, host: "Diego",
                start: inMinutes(32), duration: 5400, capacity: 10,
                attendees: ["Diego", "Sam", "Nina", "Jules", "Leo", "Maya", "Ben"], venue: Venues.yerbaBuena
            ),
            SportsEvent(
                // Popup frame: "Basketball Game · 2/3 | 1 Spot left"
                title: "Basketball Game", sport: .basketball, host: "Alex",
                start: inMinutes(60), duration: 3600, capacity: 3,
                attendees: ["Alex", "Ricardo"], venue: Venues.market760,
                notes: "Running 2v1 until someone else shows up 😅",
                messages: [msg("Alex", "Court's open, see you there", minutesAgo: 12)]
            ),
            SportsEvent(
                title: "Beach Volleyball", sport: .volleyball, host: "Sam",
                start: inMinutes(45), duration: 3600, capacity: 12,
                attendees: ["Sam", "Nina", "Jules", "Leo", "Maya", "Alex", "Priya", "Diego", "Ben"],
                venue: Venues.fourthAndMarket, skillLevel: .allLevels
            ),
            SportsEvent(
                title: "3v3 at Mint Plaza", sport: .basketball, host: "Ricardo",
                start: inMinutes(90), duration: 3600, capacity: 6,
                attendees: ["Ricardo", "Leo", "Diego", "Sam", "Ben"], venue: Venues.mintPlaza,
                skillLevel: .casual, notes: "Casual 3-on-3. One more and we're set.", otherBookmarkCount: 2
            ),
            // Full game: hidden from the map until someone drops (Settings → simulate).
            SportsEvent(
                title: "Friday Night 5v5", sport: .basketball, host: "Jules",
                start: day(1, 19), duration: 5400, capacity: 10,
                attendees: ["Jules", "Alex", "Ben", "Diego", "Leo", "Maya", "Nina", "Priya", "Ricardo", "Sam"],
                venue: Venues.kezar, skillLevel: .competitive, isBookmarked: true, otherBookmarkCount: 4
            ),

            // MARK: Registered events frame
            SportsEvent(
                title: "Sunday Sunset Jam", sport: .music, host: "Maya",
                start: day(1, 17, 30), duration: 7200, capacity: 6,
                attendees: ["Maya", "Leo", Person.you], venue: Venues.doloresPark,
                messages: [
                    msg("Maya", "Meet by the palms. I'll save us a spot!", minutesAgo: 40),
                    msg("Leo", "Bringing my guitar. See you tomorrow!", minutesAgo: 25),
                ],
                unreadCount: 2
            ),
            SportsEvent(
                title: "Basketball Game", sport: .basketball, host: "Alex",
                start: day(-1, 13, 50), duration: 3600, capacity: 3,
                attendees: ["Alex", Person.you], venue: Venues.market760,
                messages: [
                    msg("Alex", "Us in 3", minutesAgo: 60 * 26),
                    msg(Person.you, "boy", minutesAgo: 60 * 26 - 1),
                ]
            ),

            // MARK: Hosted events frame
            SportsEvent(
                title: "Sunday Coffee Walk", sport: .social, host: Person.you,
                start: day(1, 10), duration: 5400, capacity: 6,
                attendees: [Person.you, "Maya", "Leo"], venue: Venues.ritualCoffee,
                messages: [
                    msg(Person.you, "Coffee first, then a stroll to Dolores Park!", minutesAgo: 50),
                    msg("Maya", "Perfect. I'll bring my reusable cup ☕️", minutesAgo: 30),
                ],
                unreadCount: 2
            ),
            SportsEvent(
                title: "Neighborhood Game Night", sport: .games, host: Person.you,
                start: day(2, 18, 30), duration: 10800, capacity: 6,
                attendees: [Person.you, "Alex", "Priya", "Ben"], venue: Venues.missionRec,
                messages: [
                    msg(Person.you, "I'm bringing Catan. Beginners welcome!", minutesAgo: 90),
                    msg("Priya", "I'll bring snacks and a deck of cards.", minutesAgo: 15),
                ],
                unreadCount: 1
            ),
        ]
    }
}
