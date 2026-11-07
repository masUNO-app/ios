import CoreLocation
import MapKit

/// How a campus signs its students in (SPEC §8.4). Raw values match `universities.sso_provider`.
nonisolated enum SSOProvider: String, Hashable, Codable, Sendable {
    case azure, google

    /// The query parameter that sends students straight to their school's page.
    var hintParameter: String {
        switch self {
        case .azure: "domain_hint"
        case .google: "hd"
        }
    }
}

/// A campus (a row in `universities`). masUNO launches at Tec, but nothing in the app is tied
/// to it: which campuses are open is data, so the launch campus can change without a release
/// (SPEC §8.10).
nonisolated struct University: Identifiable, Hashable, Codable, Sendable {
    /// Farther than this, the map stays on campus instead of following you (App Review is far from any campus).
    static let nearbyMeters: CLLocationDistance = 15_000
    static let mapSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)

    let id: UUID
    /// "Tec de Monterrey", on the Me card.
    var name: String
    /// "Tec", in copy like "Pickup games around Tec".
    var shortName: String
    /// "tec.mx", without the @.
    var emailDomain: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// `nil` on the hidden demo campus, which only allowlisted accounts reach.
    var ssoProvider: SSOProvider?
    /// False once a campus closes: existing accounts still sign in, new ones can't.
    var signupEnabled = true

    var center: CLLocationCoordinate2D { .init(latitude: centerLatitude, longitude: centerLongitude) }
    var region: MKCoordinateRegion { .init(center: center, span: Self.mapSpan) }

    func isNearby(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: CLLocation(latitude: centerLatitude, longitude: centerLongitude)) <= Self.nearbyMeters
    }
}
