import MapKit
import UIKit

/// All inputs that affect the rendered bitmap. Point size and display scale are separate so a
/// resized thumbnail or a move between displays cannot reuse a stale-resolution image.
nonisolated struct MapSnapshotRequest: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var size: Double
    var scale: Double
    var regionMeters: Double = 400

    var cacheKey: NSString {
        "\(latitude.bitPattern):\(longitude.bitPattern):\(size.bitPattern):\(scale.bitPattern):\(regionMeters.bitPattern):light-standard-no-poi" as NSString
    }
}

/// Bounded, pressure-evictable cache shared by thumbnails. Each waiter owns only its subscription:
/// cancelling one view does not cancel a snapshot that another visible view still needs.
@MainActor
final class MapSnapshotCache: NSObject {
    static let shared = MapSnapshotCache()
    private struct Flight {
        let id: UUID
        let task: Task<UIImage, any Error>
        let reads = SharedReadPool<Int, UIImage>(resource: "mapSnapshot")
        var waiters: Set<UUID>
    }
    private let images = NSCache<NSString, UIImage>()
    private var flights: [MapSnapshotRequest: Flight] = [:]
    private let render: (MapSnapshotRequest) async throws -> UIImage

    init(maximumCost: Int = 8 * 1024 * 1024, render: @escaping (MapSnapshotRequest) async throws -> UIImage = MapSnapshotCache.render) {
        self.render = render
        super.init()
        images.totalCostLimit = maximumCost
        images.countLimit = 96
        NotificationCenter.default.addObserver(self, selector: #selector(clearForMemoryPressure), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    func image(for request: MapSnapshotRequest) async throws -> UIImage {
        try Task.checkCancellation()
        if let image = images.object(forKey: request.cacheKey) { return image }
        let waiter = UUID()
        if var flight = flights[request] {
            flight.waiters.insert(waiter)
            flights[request] = flight
        } else {
            let renderer = render
            flights[request] = Flight(id: UUID(), task: Task { try await renderer(request) }, waiters: [waiter])
        }
        guard let flight = flights[request] else { throw CancellationError() }
        let flightID = flight.id
        return try await withTaskCancellationHandler {
            defer { release(request, flightID: flightID, waiter: waiter) }
            let image = try await flight.reads.value(for: 0) { try await flight.task.value }
            try Task.checkCancellation()
            // A newer flight may have superseded this snapshot.
            if flights[request]?.id == flight.id {
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(request.size * request.size * request.scale * request.scale * 4)
                images.setObject(image, forKey: request.cacheKey, cost: cost)
            }
            return image
        } onCancel: {
            Task { @MainActor [weak self] in self?.release(request, flightID: flightID, waiter: waiter) }
        }
    }

    /// Diagnostic count also permits deterministic cancellation regression checks.
    func subscriberCount(for request: MapSnapshotRequest) -> Int { flights[request]?.waiters.count ?? 0 }

    func removeAll() {
        images.removeAllObjects()
    }

    @objc private func clearForMemoryPressure() {
        removeAll()
    }

    private func release(_ request: MapSnapshotRequest, flightID: UUID, waiter: UUID) {
        guard var flight = flights[request], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty {
            flight.task.cancel()
            flights[request] = nil
        } else {
            flights[request] = flight
        }
    }

    private static func render(_ request: MapSnapshotRequest) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        let coordinate = CLLocationCoordinate2D(latitude: request.latitude, longitude: request.longitude)
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: request.regionMeters, longitudinalMeters: request.regionMeters)
        options.size = CGSize(width: request.size, height: request.size)
        options.scale = request.scale
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshotter = MKMapSnapshotter(options: options)
        let cancellation = SnapshotCancellation { snapshotter.cancel() }
        return try await withTaskCancellationHandler {
            try await snapshotter.start().image
        } onCancel: {
            Task { @MainActor in cancellation.cancel() }
        }
    }
}

@MainActor
private final class SnapshotCancellation {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action() }
}
