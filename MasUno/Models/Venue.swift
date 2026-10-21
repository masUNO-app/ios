import CoreLocation
import Foundation

struct Venue: Hashable, Identifiable {
    var name: String
    var street: String
    var city: String
    var latitude: Double
    var longitude: Double

    var id: String { name }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// "760 Market Street, San Francisco, CA 94107"
    var fullAddress: String { "\(street), \(city)" }

    /// "Dolores Park · 19th & Dolores St" (or just the street when the venue is an address)
    var titleLine: String { name == street ? street : "\(name) · \(street)" }
}
