import MapKit
import Observation
import SwiftUI

/// "Where's the game?" (SPEC §7.6.3, 1.0): search suggestions near campus or the
/// current location, then **Set location**. Drag-to-adjust is 2.0 (E20).
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

    /// ~15 km around campus.
    private static let searchRegion = MKCoordinateRegion(
        center: Campus.center, latitudinalMeters: 30_000, longitudinalMeters: 30_000
    )

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    init(current: Place?) {
        selection = current
        position = current.map { .region(Self.region(around: $0.coordinate)) } ?? .region(Campus.region)
        super.init()
        completer.delegate = self
        completer.region = Self.searchRegion
        completer.resultTypes = [.pointOfInterest, .address]
    }

    var showsSuggestions: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Intents

    func select(_ suggestion: Suggestion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(suggestion.title) \(suggestion.subtitle)"
        request.region = Self.searchRegion
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

    private func choose(_ place: Place) {
        selection = place
        query = ""
        suggestions = []
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
