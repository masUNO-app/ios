import CoreLocation
import MapKit

/// Tec's Monterrey campus, where the map lands when your location can't be used (SPEC §7.6.1).
enum Campus {
    static let center = CLLocationCoordinate2D(latitude: 25.6514, longitude: -100.2895)
    static let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012))
    /// Farther than this, the map stays on campus instead of following you (App Review isn't in Monterrey).
    static let nearbyMeters: CLLocationDistance = 15_000

    static func isNearby(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) <= nearbyMeters
    }
}
