import Foundation
import Contacts
import MapKit
import Testing
@testable import masUNO

@MainActor
private final class PlaceResolutionGate {
    private var pending: [String: CheckedContinuation<Place, any Error>] = [:]
    private var entered: Set<String> = []
    private var waiting: [(String, CheckedContinuation<Void, Never>)] = []

    func resolve(_ name: String) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            pending[name] = continuation
            entered.insert(name)
            let ready = waiting.filter { $0.0 == name }
            waiting.removeAll { $0.0 == name }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitFor(_ name: String) async {
        guard !entered.contains(name) else { return }
        await withCheckedContinuation { waiting.append((name, $0)) }
    }

    // Deliberately ignores cancellation until the test completes the operation, matching a
    // service that can still deliver a callback after cancellation.
    func finish(_ name: String, with result: Result<Place, any Error>) {
        pending.removeValue(forKey: name)?.resume(with: result)
    }
}

@MainActor
private final class PickerClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
struct LocationResolutionTests {
    private let oldPlace = Place(name: "Old", address: "", latitude: 25.65, longitude: -100.29)
    private let first = Place(name: "First", address: "", latitude: 25.66, longitude: -100.28)
    private let second = Place(name: "Second", address: "", latitude: 25.67, longitude: -100.27)

    @Test func legacyAddressMappingKeepsExactPinInsteadOfNearbyStreetCoordinate() {
        let address = CNMutablePostalAddress()
        address.street = "123 Campus Drive"
        address.city = "Monterrey"
        address.country = "Mexico"
        let nearby = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 25.66, longitude: -100.28),
            postalAddress: address
        )
        let requested = CLLocation(latitude: 25.660123, longitude: -100.280456)
        let place = Place(placemark: nearby, location: requested, fallbackName: "Dropped pin")

        #expect(place.latitude == requested.coordinate.latitude)
        #expect(place.longitude == requested.coordinate.longitude)
        #expect(place.address.contains("123 Campus Drive"))
        #expect(place.address.contains("Monterrey"))
        #expect(!place.address.contains("\n"))
    }

    @Test func missingGeocoderResultKeepsFixAndFallbackLabel() {
        let location = CLLocation(latitude: 25.660123, longitude: -100.280456)
        let place = Place(placemark: nil, location: location, fallbackName: "Current location")
        #expect(place.name == "Current location")
        #expect(place.address.isEmpty)
        #expect(place.latitude == location.coordinate.latitude)
        #expect(place.longitude == location.coordinate.longitude)
    }

    @Test func directionsAndSearchConversionKeepDestinationNameAndCoordinate() {
        let location = CLLocation(latitude: 25.660123, longitude: -100.280456)
        let destination = LocationService.mapItem(location: location, name: "Campus court")
        let place = Place(mapItem: destination, fallbackName: "Search query")
        #expect(place.name == "Campus court")
        #expect(place.latitude == location.coordinate.latitude)
        #expect(place.longitude == location.coordinate.longitude)
    }

    private func model(_ gate: PlaceResolutionGate, clock: PickerClock = PickerClock()) -> LocationPickerViewModel {
        let services = LocationPickerServices(
            suggestion: { query, _ in try await gate.resolve(query.trimmingCharacters(in: .whitespaces)) },
            currentPlace: { try await gate.resolve("current") },
            reverse: { _ in try await gate.resolve("reverse") }
        )
        return LocationPickerViewModel(current: oldPlace, campus: nil, services: services, now: { clock.now })
    }

    @Test func olderReplyCannotReplaceANewerSelectionOrClearItsSpinner() async {
        let gate = PlaceResolutionGate()
        let vm = model(gate)
        let a = Task { await vm.select(.init(title: "A", subtitle: "")) }
        await gate.waitFor("A")
        #expect(vm.isResolving)
        #expect(!vm.canConfirm)
        let b = Task { await vm.select(.init(title: "B", subtitle: "")) }
        await gate.waitFor("B")
        gate.finish("A", with: .success(first))
        await a.value
        #expect(vm.selection == oldPlace)
        #expect(vm.isResolving)
        #expect(!vm.canConfirm)
        gate.finish("B", with: .success(second))
        await b.value
        #expect(vm.selection == second)
        #expect(vm.canConfirm)
    }

    @Test func staleFailureAfterNewerSuccessDoesNotShowAnError() async {
        let gate = PlaceResolutionGate()
        let vm = model(gate)
        let a = Task { await vm.select(.init(title: "A", subtitle: "")) }
        await gate.waitFor("A")
        let b = Task { await vm.select(.init(title: "B", subtitle: "")) }
        await gate.waitFor("B")
        gate.finish("B", with: .success(second))
        await b.value
        gate.finish("A", with: .failure(URLError(.notConnectedToInternet)))
        await a.value
        #expect(vm.selection == second)
        #expect(vm.errorMessage == nil)
        #expect(vm.canConfirm)
    }

    @Test func dragSupersedesCurrentLocationAndKeepsExactPinOnAddressFailure() async {
        let gate = PlaceResolutionGate()
        let clock = PickerClock()
        let vm = model(gate, clock: clock)
        let location = Task { await vm.useCurrentLocation() }
        await gate.waitFor("current")
        clock.now = clock.now.addingTimeInterval(2)
        let coordinate = CLLocationCoordinate2D(latitude: 25.68, longitude: -100.26)
        let drag = Task { await vm.mapSettled(at: coordinate) }
        await gate.waitFor("reverse")
        #expect(vm.selection?.coordinate.latitude == coordinate.latitude)
        #expect(!vm.canConfirm)
        gate.finish("current", with: .success(first))
        await location.value
        #expect(vm.isResolving)
        gate.finish("reverse", with: .failure(URLError(.notConnectedToInternet)))
        await drag.value
        #expect(vm.selection?.coordinate.latitude == coordinate.latitude)
        #expect(vm.selection?.coordinate.longitude == coordinate.longitude)
        #expect(vm.canConfirm)
    }

    @Test func leavingPreventsLatePublicationAndQueuedRequests() async {
        let gate = PlaceResolutionGate()
        let vm = model(gate)
        let task = Task { await vm.select(.init(title: "A", subtitle: "")) }
        await gate.waitFor("A")
        vm.cancelResolution()
        gate.finish("A", with: .success(first))
        await task.value
        await vm.useCurrentLocation()
        #expect(vm.selection == oldPlace)
        #expect(!vm.isResolving)
        #expect(vm.errorMessage == nil)
    }
}
