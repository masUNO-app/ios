import Foundation
import Testing
@testable import masUNO

@MainActor
struct SharedReadPoolTests {
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition(), "Expected task interleaving did not occur")
    }

    @Test func matchingWaitersStartOneRequest() async throws {
        let gate = NotificationTestGate()
        let pool = SharedReadPool<String, Int>(resource: "test")
        var calls = 0
        let first = Task { try await pool.value(for: "same") { calls += 1; await gate.wait(); return 7 } }
        await gate.waitUntilEntered()
        let second = Task { try await pool.value(for: "same") { calls += 1; return 9 } }
        await until { pool.statistics.shared == 1 }
        gate.open()
        #expect(try await first.value == 7)
        #expect(try await second.value == 7)
        #expect(calls == 1)
        #expect(pool.statistics.active == 0)
    }

    @Test func cancellingOneWaiterReturnsWithoutCancellingTheOther() async throws {
        let gate = NotificationTestGate()
        let pool = SharedReadPool<String, Int>(resource: "test")
        let first = Task { try await pool.value(for: "same") { await gate.wait(); return 7 } }
        await gate.waitUntilEntered()
        let second = Task { try await pool.value(for: "same") { 9 } }
        await until { pool.statistics.shared == 1 }
        first.cancel()
        do { _ = try await first.value; Issue.record("Cancelled waiter returned a value") }
        catch { #expect(OperationCancellation.isCancellation(error)) }
        #expect(pool.statistics.active == 1)
        gate.open()
        #expect(try await second.value == 7)
    }

    @Test func oldCompletionCannotRemoveANewerFlight() async throws {
        let oldGate = NotificationTestGate()
        let newGate = NotificationTestGate()
        let pool = SharedReadPool<String, Int>(resource: "test")
        let old = Task { try await pool.value(for: "same") { await oldGate.wait(); return 1 } }
        await oldGate.waitUntilEntered()
        pool.cancelAll()
        let replacement = Task { try await pool.value(for: "same") { await newGate.wait(); return 2 } }
        await newGate.waitUntilEntered()
        oldGate.open()
        do { _ = try await old.value; Issue.record("Reset read returned a value") }
        catch { #expect(OperationCancellation.isCancellation(error)) }
        #expect(pool.statistics.active == 1)
        newGate.open()
        #expect(try await replacement.value == 2)
    }

    @Test func failedReadDoesNotPoisonRetry() async throws {
        let pool = SharedReadPool<String, Int>(resource: "test")
        do { _ = try await pool.value(for: "same") { throw DomainError.offline }; Issue.record("Expected offline") }
        catch { #expect(error as? DomainError == .offline) }
        #expect(try await pool.value(for: "same") { 8 } == 8)
        #expect(pool.statistics.started == 2)
    }

    @Test func concurrencyLimitAppliesAcrossDifferentKeys() async throws {
        let gate = NotificationTestGate()
        let pool = SharedReadPool<Int, Int>(resource: "test", limit: 2)
        var active = 0
        var peak = 0
        let tasks = (0..<8).map { key in
            Task { try await pool.value(for: key) {
                active += 1; peak = max(peak, active)
                await gate.wait()
                active -= 1
                return key
            } }
        }
        await until { active == 2 && pool.statistics.started == 8 }
        #expect(peak == 2)
        gate.open()
        for task in tasks { _ = try await task.value }
        #expect(peak <= 2)
        #expect(active == 0)
    }
}
