import Foundation
import UIKit
import Testing
@testable import masUNO

@MainActor
private final class SnapshotRenderGate {
    private var continuation: CheckedContinuation<UIImage, any Error>?
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0

    func render() async throws -> UIImage {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            entered = true
            observers.forEach { $0.resume() }
            observers = []
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func finish(_ image: UIImage) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

@MainActor
struct MapSnapshotCacheTests {
    private let request = MapSnapshotRequest(latitude: 25.65, longitude: -100.29, size: 48, scale: 2)

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test func cacheIdentityIncludesDimensionsScaleRegionAndScheme() {
        var resized = request
        resized.size = 72
        var scaled = request
        scaled.scale = 3
        var zoomed = request
        zoomed.regionMeters = 800
        var dark = request
        dark.isDark = true
        #expect(Set([request, resized, scaled, zoomed, dark]).count == 5)
        #expect(Set([request.cacheKey, resized.cacheKey, scaled.cacheKey, zoomed.cacheKey, dark.cacheKey]).count == 5)
    }

    @Test func lightAndDarkSnapshotsAreRenderedAndCachedSeparately() async throws {
        let light = image(), darkImage = image()
        var dark = request
        dark.isDark = true
        var rendered: [Bool] = []
        let cache = MapSnapshotCache { request in rendered.append(request.isDark); return request.isDark ? darkImage : light }
        #expect(try await cache.image(for: request) === light)
        #expect(try await cache.image(for: dark) === darkImage)
        #expect(try await cache.image(for: request) === light)
        #expect(rendered == [false, true])
    }

    @Test func equalSnapshotsReuseTheCachedImageAndClearingRequiresANewRender() async throws {
        let expected = image()
        var calls = 0
        let cache = MapSnapshotCache { _ in calls += 1; return expected }
        #expect(try await cache.image(for: request) === expected)
        #expect(try await cache.image(for: request) === expected)
        #expect(calls == 1)
        cache.removeAll()
        #expect(try await cache.image(for: request) === expected)
        #expect(calls == 2)
    }

    @Test func changingScaleActuallyRendersADifferentBitmap() async throws {
        let expected = image()
        var calls = 0
        let cache = MapSnapshotCache { _ in calls += 1; return expected }
        _ = try await cache.image(for: request)
        var scaled = request
        scaled.scale = 3
        _ = try await cache.image(for: scaled)
        #expect(calls == 2)
    }

    @Test func cancellingOneWaiterDoesNotCancelAnotherViewsSnapshot() async throws {
        let gate = SnapshotRenderGate()
        let cache = MapSnapshotCache { _ in try await gate.render() }
        let first = Task { try await cache.image(for: request) }
        await gate.waitUntilEntered()
        let second = Task { try await cache.image(for: request) }
        // Wait for the actual second subscription, not a guessed network delay.
        for _ in 0..<100 where cache.subscriberCount(for: request) < 2 { await Task.yield() }
        #expect(cache.subscriberCount(for: request) == 2)
        first.cancel()
        await Task.yield()
        let expected = image()
        gate.finish(expected)
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(try await second.value === expected)
        #expect(gate.calls == 1)
    }
}
