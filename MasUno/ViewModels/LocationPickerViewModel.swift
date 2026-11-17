import MapKit
import Observation
import SwiftUI

/// Small injected boundary lets selection races be tested without issuing real MapKit requests.
struct LocationPickerServices {
    var suggestion: (String, MKCoordinateRegion?) async throws -> Place
    var currentPlace: () async throws -> Place
    var reverse: (CLLocationCoordinate2D) async throws -> Place

    static let live = LocationPickerServices(
        suggestion: { query, region in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let region { request.region = region }
            let search = MKLocalSearch(request: request)
            let cancellation = LocationRequestCancellation { search.cancel() }
            let response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                Task { @MainActor in cancellation.cancel() }
            }
            try Task.checkCancellation()
            guard let item = response.mapItems.first else { throw LocationService.Failure.unavailable }
            return Place(mapItem: item, fallbackName: query)
        },
        currentPlace: { try await LocationService.currentPlace() },
        reverse: { coordinate in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return try await LocationService.reversePlace(at: location, fallbackName: String(localized: "Dropped pin"))
        }
    )
}

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
    @ObservationIgnored private var ignoresCameraUntil: Date
    /// The newest drag wins when lookups overlap.
    @ObservationIgnored private var acceptsResolutions = true
    @ObservationIgnored private var lookup = UUID()
    @ObservationIgnored private var resolutionTask: Task<Place, any Error>?
    @ObservationIgnored private let services: LocationPickerServices
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    init(current: Place?, campus: University?, services: LocationPickerServices = .live, now: @escaping () -> Date = { .now }) {
        self.services = services
        self.now = now
        ignoresCameraUntil = now().addingTimeInterval(1.2)
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

    /// The previous place can remain as context while resolving, but cannot be confirmed.
    var canConfirm: Bool { selection != nil && !isResolving }

    func select(_ suggestion: Suggestion) async {
        guard acceptsResolutions else { return }
        let token = beginResolution()
        let query = "\(suggestion.title) \(suggestion.subtitle)"
        let service = services.suggestion
        let region = searchRegion
        let task = Task { try await service(query, region) }
        resolutionTask = task
        defer { finishResolution(token) }
        do {
            let place = try await task.value
            guard lookup == token, !Task.isCancelled else { return }
            choose(place)
        } catch {
            guard lookup == token, !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            errorMessage = String(localized: "Couldn't find that place. Try another search.")
        }
    }

    func useCurrentLocation() async {
        guard acceptsResolutions else { return }
        let token = beginResolution()
        let service = services.currentPlace
        let task = Task { try await service() }
        resolutionTask = task
        defer { finishResolution(token) }
        do {
            let place = try await task.value
            guard lookup == token, !Task.isCancelled else { return }
            choose(place)
        } catch {
            guard lookup == token, !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            if case LocationService.Failure.denied = error {
                errorMessage = String(localized: "Turn on location in Settings to use where you are.")
            } else {
                errorMessage = String(localized: "Couldn't get your location. Try searching instead.")
            }
        }
    }

    /// The camera moved under the pin. Each drag is a new intent, shared with suggestion and
    /// current-location requests. Reverse-geocoding failure keeps the exact dropped coordinate.
    func mapSettled(at center: CLLocationCoordinate2D) async {
        guard acceptsResolutions, now() > ignoresCameraUntil else { return }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if let selection, here.distance(from: CLLocation(latitude: selection.latitude, longitude: selection.longitude)) < 15 { return }
        let token = beginResolution()
        selection = Place(name: String(localized: "Dropped pin"), address: "", latitude: center.latitude, longitude: center.longitude)
        let service = services.reverse
        let task = Task { try await service(center) }
        resolutionTask = task
        defer { finishResolution(token) }
        do {
            let place = try await task.value
            guard lookup == token, !Task.isCancelled else { return }
            selection = place
        } catch {
            // Keep the exact dropped pin if the address is unavailable. Superseded work has
            // no authority over either the selection, the error, or a newer loading indicator.
        }
    }

    func resumeResolution() { acceptsResolutions = true }

    func cancelResolution() {
        acceptsResolutions = false
        lookup = UUID()
        resolutionTask?.cancel()
        resolutionTask = nil
        isResolving = false
        completer.cancel()
    }

    private func beginResolution() -> UUID {
        resolutionTask?.cancel()
        lookup = UUID()
        isResolving = true
        errorMessage = nil
        return lookup
    }

    private func finishResolution(_ token: UUID) {
        guard lookup == token else { return }
        resolutionTask = nil
        isResolving = false
    }

    private func choose(_ place: Place) {
        selection = place
        query = ""
        suggestions = []
        ignoresCameraUntil = now().addingTimeInterval(1.5)
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
