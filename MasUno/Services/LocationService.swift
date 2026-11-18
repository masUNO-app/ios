import CoreLocation
import Contacts
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
    static func currentLocation(timeout: Duration = .seconds(15)) async throws -> CLLocation {
        if let mock = mockCoordinate {
            return CLLocation(latitude: mock.latitude, longitude: mock.longitude)
        }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { try await oneShotLocation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.unavailable
            }
            defer { group.cancelAll() }
            guard let location = try await group.next() else { throw Failure.unavailable }
            return location
        }
    }

    private static func oneShotLocation() async throws -> CLLocation {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            try Task.checkCancellation()
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw Failure.denied }
            if let location = update.location { return location }
        }
        throw Failure.unavailable
    }

    /// Current location as a place, named from a reverse-geocoded address.
    static func currentPlace() async throws -> Place {
        let location = try await currentLocation()
        try Task.checkCancellation()
        let fallbackName = String(localized: "Current location", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        let place = try? await reversePlace(at: location, fallbackName: fallbackName)
        try Task.checkCancellation()
        return place ?? Place(mapItem: nil, location: location, fallbackName: fallbackName)
    }

    /// Resolves an address without replacing the requested coordinate with the geocoder's
    /// nearby address coordinate. A cancelled lookup also cancels its underlying request.
    static func reversePlace(at location: CLLocation, fallbackName: String) async throws -> Place {
        try Task.checkCancellation()
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { throw Failure.unavailable }
            let cancellation = LocationRequestCancellation { request.cancel() }
            let place: Place = try await withTaskCancellationHandler {
                // Older SDKs import the async mapItems property as nonisolated. Convert
                // the callback's MapKit objects before resuming with our Sendable value.
                try await withCheckedThrowingContinuation { continuation in
                    request.getMapItems { items, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: Place(
                                mapItem: items?.first, location: location, fallbackName: fallbackName
                            ))
                        }
                    }
                }
            } onCancel: {
                Task { @MainActor in cancellation.cancel() }
            }
            try Task.checkCancellation()
            return place
        } else {
            let geocoder = CLGeocoder()
            let cancellation = LocationRequestCancellation { geocoder.cancelGeocode() }
            let placemarks = try await withTaskCancellationHandler {
                try await geocoder.reverseGeocodeLocation(location)
            } onCancel: {
                Task { @MainActor in cancellation.cancel() }
            }
            try Task.checkCancellation()
            return Place(placemark: placemarks.first, location: location, fallbackName: fallbackName)
        }
    }

    /// Shared by event details and notification actions so walking directions use the same
    /// exact destination on every supported OS.
    static func mapItem(location: CLLocation, name: String) -> MKMapItem {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: location, address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        }
        item.name = name
        return item
    }
}

@MainActor
final class LocationRequestCancellation {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action() }
}

extension Place {
    /// Search results choose their own coordinate; reverse lookups pass their original fix
    /// explicitly to the initializer below.
    nonisolated init(mapItem: MKMapItem, fallbackName: String) {
        let location: CLLocation
        if #available(iOS 26.0, *) {
            location = mapItem.location
        } else {
            location = mapItem.placemark.location ?? CLLocation(
                latitude: mapItem.placemark.coordinate.latitude,
                longitude: mapItem.placemark.coordinate.longitude
            )
        }
        self.init(mapItem: mapItem, location: location, fallbackName: fallbackName)
    }

    /// Builds a place from a MapKit result. Name falls back to the street, then to `fallbackName`.
    nonisolated init(mapItem: MKMapItem?, location: CLLocation, fallbackName: String) {
        if #available(iOS 26.0, *) {
            let street = mapItem?.address?.shortAddress ?? ""
            let full = (mapItem?.address?.fullAddress ?? "").replacingOccurrences(of: "\n", with: ", ")
            self.init(
                name: mapItem?.name ?? (street.isEmpty ? fallbackName : street),
                address: full,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } else {
            self.init(placemark: mapItem?.placemark, location: location, fallbackName: mapItem?.name ?? fallbackName)
            if let name = mapItem?.name { self.name = name }
        }
    }

    nonisolated init(placemark: CLPlacemark?, location: CLLocation, fallbackName: String) {
        let street = [placemark?.subThoroughfare, placemark?.thoroughfare]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let full = placemark?.postalAddress.map {
            CNPostalAddressFormatter.string(from: $0, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        } ?? ""
        self.init(
            name: placemark?.name ?? (street.isEmpty ? fallbackName : street),
            address: full,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
