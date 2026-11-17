import Foundation
import OSLog

/// Shares equivalent reads without giving one view ownership of another view's request.
/// Cancelling a waiter resumes it immediately; the underlying task is cancelled only when
/// nobody needs it, or the account context is cleared. Completed values are not cached here.
@MainActor
final class SharedReadPool<Key: Hashable & Sendable, Value: Sendable> {
    struct Statistics: Equatable {
        var started = 0
        var shared = 0
        var cancelledWaiters = 0
        var active = 0
    }

    private struct Flight {
        let id: UUID
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<Value, any Error>]
    }

    private var flights: [Key: Flight] = [:]
    private(set) var statistics = Statistics()
    private let logger = Logger(subsystem: "com.masuno.app", category: "Reads")
    private let resource: String
    private let limiter: ReadConcurrencyLimiter?

    init(resource: String, limit: Int? = nil) {
        self.resource = resource
        limiter = limit.map { ReadConcurrencyLimiter(limit: $0) }
    }

    // Swift 6.3 crashes optimizing a generic isolated deinit when deploying before iOS 26
    // (swiftlang/swift#90625). No actor-bound cleanup is needed; keep destruction nonisolated.
    nonisolated deinit {}

    func value(for key: Key, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value: Value = try await withCheckedThrowingContinuation { continuation in
                if var flight = flights[key] {
                    flight.waiters[waiter] = continuation
                    flights[key] = flight
                    statistics.shared += 1
                    return
                }
                let id = UUID()
                let started = ContinuousClock.now
                flights[key] = Flight(id: id, waiters: [waiter: continuation])
                statistics.started += 1
                statistics.active += 1
                let task = Task { [weak self] in
                    let result: Result<Value, any Error>
                    do {
                        if let limiter = self?.limiter {
                            result = .success(try await limiter.run(operation))
                        } else {
                            result = .success(try await operation())
                        }
                    }
                    catch { result = .failure(error) }
                    self?.finish(key, id: id, result: result, elapsed: ContinuousClock.now - started)
                }
                flights[key]?.task = task
            }
            try Task.checkCancellation()
            return value
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(key, waiter: waiter) }
        }
    }

    func cancelAll() {
        let held = flights
        flights.removeAll()
        statistics.active = 0
        for flight in held.values {
            flight.task?.cancel()
            for continuation in flight.waiters.values { continuation.resume(throwing: CancellationError()) }
        }
    }

    private func cancel(_ key: Key, waiter: UUID) {
        guard var flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        statistics.cancelledWaiters += 1
        if flight.waiters.isEmpty {
            flights[key] = nil
            statistics.active -= 1
            flight.task?.cancel()
        } else {
            flights[key] = flight
        }
        continuation.resume(throwing: CancellationError())
    }

    private func finish(_ key: Key, id: UUID, result: Result<Value, any Error>, elapsed: Duration) {
        guard let flight = flights[key], flight.id == id else { return }
        flights[key] = nil
        statistics.active -= 1
        // Resource labels are fixed by call sites; no account IDs, locations, or content are logged.
        logger.debug("\(self.resource, privacy: .public) finished in \(String(describing: elapsed), privacy: .public)")
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }
}

@MainActor
private final class ReadConcurrencyLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [(UUID, CheckedContinuation<Void, any Error>)] = []

    init(limit: Int) { self.limit = max(limit, 1) }

    func run<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if active < limit {
                active += 1
            } else {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
                waiters.remove(at: index).1.resume(throwing: CancellationError())
            }
        }
        defer {
            if waiters.isEmpty { active -= 1 }
            else { waiters.removeFirst().1.resume() }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}
