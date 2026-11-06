import CoreLocation
import MapKit

/// Tec's Monterrey campus, where the map lands when your location can't be used (SPEC §7.6.1).
enum Campus {
    static let center = CLLocationCoordinate2D(latitude: 25.6514, longitude: -100.2895)
    static let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012))
    /// TODO/TEMP(E9): where "you" are pinned until the live map lands.
    static let mockUser = CLLocationCoordinate2D(latitude: 25.6533, longitude: -100.2872)
}
