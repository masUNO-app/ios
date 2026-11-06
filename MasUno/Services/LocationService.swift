import CoreLocation
import MapKit

/// The phone's location, used on the phone only (SPEC §8.8): a one-shot fix for
/// "Use my current location" (E8) and the map's first position (E9).
enum LocationService {
    enum Failure: Error {
        case denied, unavailable
    }

    /// DEBUG only: `-mockLocation YES` pins "you" just north-east of campus, for simulators
    /// and design review. Always nil in Release (N27).
    static var mockCoordinate: CLLocationCoordinate2D? {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "mockLocation") ? CLLocationCoordinate2D(latitude: 25.6533, longitude: -100.2872) : nil
        #else
        nil
        #endif
    }

    /// Asks for When-In-Use permission if needed, then returns the first location fix.
    static func currentLocation() async throws -> CLLocation {
        if let mock = mockCoordinate {
            return CLLocation(latitude: mock.latitude, longitude: mock.longitude)
        }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw Failure.denied }
            if let location = update.location { return location }
        }
        throw Failure.unavailable
    }

    /// Current location as a place, named from a reverse-geocoded address.
    static func currentPlace() async throws -> Place {
        let location = try await currentLocation()
        let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first
        return Place(mapItem: item, location: location, fallbackName: String(localized: "Current location"))
    }
}

extension Place {
    /// Builds a place from a MapKit result. Name falls back to the street, then to `fallbackName`.
    nonisolated init(mapItem: MKMapItem?, location: CLLocation, fallbackName: String) {
        let street = mapItem?.address?.shortAddress ?? ""
        let full = (mapItem?.address?.fullAddress ?? "").replacingOccurrences(of: "\n", with: ", ")
        self.init(
            name: mapItem?.name ?? (street.isEmpty ? fallbackName : street),
            address: full,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
