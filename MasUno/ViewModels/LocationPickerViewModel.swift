import MapKit
import Observation
import SwiftUI

/// "Where's the game?" (SPEC §7.6.3): search suggestions near campus or the current location,
/// or drag the map under the fixed pin and the address follows (E20). Then **Set location**.
@Observable
final class LocationPickerViewModel: NSObject {
    struct Suggestion: Identifiable, Hashable {
        var id: String { "\(title)|\(subtitle)" }
        var title: String
        var subtitle: String
    }

    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var suggestions: [Suggestion] = []
    /// The spot that **Set location** will save.
    private(set) var selection: Place?
    private(set) var isResolving = false
    var errorMessage: String?
    var position: MapCameraPosition

    /// ~15 km around your campus.
    private let searchRegion: MKCoordinateRegion?
    /// Camera moves before this are ours (opening, flying to a search result), not a drag.
    @ObservationIgnored private var ignoresCameraUntil = Date.now.addingTimeInterval(1.2)
    /// The newest drag wins when lookups overlap.
    @ObservationIgnored private var lookup = 0

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    init(current: Place?, campus: University?) {
        selection = current
        searchRegion = campus.map { MKCoordinateRegion(center: $0.center, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
        position = current.map { .region(Self.region(around: $0.coordinate)) } ?? campus.map { .region($0.region) } ?? .automatic
        super.init()
        completer.delegate = self
        if let searchRegion { completer.region = searchRegion }
        completer.resultTypes = [.pointOfInterest, .address]
    }

    var showsSuggestions: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Intents

    func select(_ suggestion: Suggestion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(suggestion.title) \(suggestion.subtitle)"
        if let searchRegion { request.region = searchRegion }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            errorMessage = String(localized: "Couldn't find that place. Try another search.")
            return
        }
        choose(Place(mapItem: item, location: item.location, fallbackName: suggestion.title))
    }

    func useCurrentLocation() async {
        isResolving = true
        defer { isResolving = false }
        do {
            choose(try await LocationService.currentPlace())
        } catch LocationService.Failure.denied {
            errorMessage = String(localized: "Turn on location in Settings to use where you are.")
        } catch {
            errorMessage = String(localized: "Couldn't get your location. Try searching instead.")
        }
    }

    /// The map stopped under the pin. A drag moves the selection there and looks up its address;
    /// the app's own camera moves, and anything within a few steps of the selection, don't.
    func mapSettled(at center: CLLocationCoordinate2D) async {
        guard Date.now > ignoresCameraUntil else { return }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if let selection, here.distance(from: CLLocation(latitude: selection.latitude, longitude: selection.longitude)) < 15 { return }

        lookup += 1
        let current = lookup
        isResolving = true
        let item = try? await MKReverseGeocodingRequest(location: here)?.mapItems.first
        guard current == lookup else { return }
        isResolving = false
        selection = Place(mapItem: item, location: here, fallbackName: String(localized: "Dropped pin"))
    }

    private func choose(_ place: Place) {
        lookup += 1
        selection = place
        query = ""
        suggestions = []
        ignoresCameraUntil = Date.now.addingTimeInterval(1.5)
        withAnimation { position = .region(Self.region(around: place.coordinate)) }
    }

    private static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
    }
}

extension LocationPickerViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(5).map { Suggestion(title: $0.title, subtitle: $0.subtitle) }
        // The completer calls back on the main thread.
        MainActor.assumeIsolated { suggestions = Array(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}
