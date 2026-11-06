import CoreLocation
import Foundation

/// Where a game happens (`place_name`, `place_address`, `lat`, `lng`).
/// The meet-up spot is separate: `Game.meetPoint`.
nonisolated struct Place: Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
