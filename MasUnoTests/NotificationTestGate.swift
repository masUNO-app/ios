import Foundation

/// A deterministic suspension point for network interleavings in notification tests.
@MainActor
final class NotificationTestGate {
    private var entered = false
    private var opened = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let ready = enteredWaiters
        enteredWaiters = []
        for waiter in ready { waiter.resume() }
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        opened = true
        let ready = waiters
        waiters = []
        for waiter in ready { waiter.resume() }
    }
}
