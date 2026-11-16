import Foundation
import Testing
@testable import masUNO

nonisolated private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [String] = []

    func add(_ step: String) {
        lock.lock()
        steps.append(step)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

nonisolated private final class PrefLog: @unchecked Sendable {
    private let lock = NSLock()
    private var prefs: [NotificationPrefs] = []

    func add(_ prefs: NotificationPrefs) {
        lock.lock()
        self.prefs.append(prefs)
        lock.unlock()
    }

    var snapshot: [NotificationPrefs] {
        lock.lock()
        defer { lock.unlock() }
        return prefs
    }
}

nonisolated private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

@MainActor
@Suite(.serialized)
struct NotificationReviewTests {
    @Test func aSlowToggleDoesntOverwriteALaterOne() async {
        let queue = NotificationPrefQueue(.standard)
        let log = PrefLog()
        let gate = Gate()
        queue.set(\.reminders, to: false, send: { prefs in
            log.add(prefs)
            await gate.wait()
        }, onFailure: { _ in })
        for _ in 0..<100 where log.snapshot.isEmpty {
            await Task.yield()
        }
        #expect(!log.snapshot.isEmpty)
        queue.set(\.chat, to: false, send: { prefs in
            log.add(prefs)
        }, onFailure: { _ in })
        gate.open()
        await queue.wait()
        let sent = log.snapshot
        #expect(sent.count == 2)
        #expect(sent.first?.reminders == false)
        #expect(sent.first?.chat == true)
        #expect(sent.last?.reminders == false)
        #expect(sent.last?.chat == false)
        #expect(queue.displayed.reminders == false)
        #expect(queue.displayed.chat == false)
    }

    @Test func aFailedTogglePutsBackOnlyThatSwitch() async {
        let queue = NotificationPrefQueue(.standard)
        let log = PrefLog()
        queue.set(\.reminders, to: false, send: { _ in
            throw DomainError.offline
        }, onFailure: { _ in })
        queue.set(\.chat, to: false, send: { prefs in
            log.add(prefs)
        }, onFailure: { _ in })
        await queue.wait()
        #expect(queue.displayed.reminders == true)
        #expect(queue.displayed.chat == false)
        #expect(log.snapshot.last?.reminders == true)
        #expect(log.snapshot.last?.chat == false)
    }

    @Test func swipingThePrimerAwayCountsOnce() {
        let defaults = UserDefaults(suiteName: "Primer.\(UUID().uuidString)")!
        let backend = MockBackend()
        let push = PushNotificationService(repository: backend, games: backend, chat: backend, defaults: defaults)
        let id = UUID()
        push.recordPrimerClose(accepted: false, accountID: id)
        #expect(push.shouldOfferPrimer(accountID: id))
        push.recordPrimerClose(accepted: true, accountID: id)
        #expect(push.shouldOfferPrimer(accountID: id))
        push.recordPrimerClose(accepted: false, accountID: id)
        #expect(!push.shouldOfferPrimer(accountID: id))
    }

    @Test func aTapDuringOnboardingOpensAfterSignIn() async throws {
        let auth = MockBackend(state: .signedOut(expired: true))
        let model = AppViewModel(auth: auth, catalog: auth)
        let id = UUID()
        let url = try #require(URL(string: "masuno://game/\(id.uuidString)"))
        model.deliverPushRoute(url)
        #expect(model.path.isEmpty)
        try await auth.signIn(email: MockFixtures.reviewEmail, password: MockFixtures.reviewPassword)
        model.deliverPushRoute(nil)
        #expect(model.path == [.game(id)])
    }

    @Test func aTapWhileSignedInOpensImmediately() throws {
        let auth = MockBackend()
        let model = AppViewModel(auth: auth, catalog: auth)
        let id = UUID()
        let url = try #require(URL(string: "masuno://game/\(id.uuidString)"))
        model.deliverPushRoute(url)
        #expect(model.path == [.game(id)])
    }

    @Test func aBackgroundTapRestoresTheSessionBeforeItRuns() async {
        let box = ServiceBox()
        let backend = MockBackend()
        let defaults = UserDefaults(suiteName: "Background.\(UUID().uuidString)")!
        let push = PushNotificationService(repository: backend, games: backend, chat: backend, defaults: defaults)
        _ = box.install(push)
        let order = StepLog()
        let tap = PendingTap(action: "REPLY", payload: nil, reply: "On my way")
        await handleNotificationTap(restore: {
            order.add("restore")
        }, box: box, tap: tap) { _, tap in
            order.add(tap.reply ?? "handle")
        }
        #expect(order.snapshot == ["restore", "On my way"])
    }

    @Test func aTapBeforeTheServiceExistsWaits() async {
        let box = ServiceBox()
        let tap = PendingTap(action: "COUNT_ME_IN", payload: nil, reply: nil)
        let order = StepLog()
        await handleNotificationTap(restore: {
            order.add("restore")
        }, box: box, tap: tap) { _, _ in
            order.add("handle")
        }
        #expect(order.snapshot == ["restore"])
        let backend = MockBackend()
        let defaults = UserDefaults(suiteName: "BackgroundWait.\(UUID().uuidString)")!
        let push = PushNotificationService(repository: backend, games: backend, chat: backend, defaults: defaults)
        let waiting = box.install(push)
        #expect(waiting.map(\.action) == ["COUNT_ME_IN"])
        #expect(box.service(for: tap) === push)
    }
}
