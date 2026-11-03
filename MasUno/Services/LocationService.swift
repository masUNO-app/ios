import CoreLocation
import MapKit

/// The phone's location, used on the phone only (SPEC §8.8). E8 needs a one-shot
/// fix for "Use my current location"; E9 extends this for the live map.
enum LocationService {
    enum Failure: Error {
        case denied, unavailable
    }

    /// Asks for When-In-Use permission if needed, then returns the first location fix.
    static func currentLocation() async throws -> CLLocation {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw Failure.denied }
            if let location = update.location { return location }
        }
        throw Failure.unavailable
    }

    /// Current location as a venue, named from a reverse-geocoded address.
    static func currentVenue() async throws -> Venue {
        let location = try await currentLocation()
        let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first
        return Venue(mapItem: item, location: location, fallbackName: String(localized: "Current location"))
    }
}

extension Venue {
    /// Builds a venue from a MapKit result. Name falls back to the street, then to `fallbackName`.
    init(mapItem: MKMapItem?, location: CLLocation, fallbackName: String) {
        let street = mapItem?.address?.shortAddress ?? ""
        let full = mapItem?.address?.fullAddress ?? ""
        // `fullAddress` repeats the street; keep only what follows it for the city line.
        let city = full.hasPrefix(street) && !street.isEmpty
            ? full.dropFirst(street.count).trimmingCharacters(in: CharacterSet(charactersIn: ", \n"))
            : full
        self.init(
            name: mapItem?.name ?? (street.isEmpty ? fallbackName : street),
            street: street,
            city: city.replacingOccurrences(of: "\n", with: ", "),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
