import Foundation
import Observation

/// One preference save at a time. A later toggle is what the server ends up with, and a failure
/// puts back only the switch that failed.
@MainActor
@Observable
final class NotificationPrefQueue {
    private(set) var displayed: NotificationPrefs
    /// Counts switch flips, so a read that started before one doesn't overwrite it.
    private(set) var edits = 0
    private var accepted: NotificationPrefs
    private var chain: Task<Void, Never>?
    private var generations: [WritableKeyPath<NotificationPrefs, Bool>: Int] = [:]

    init(_ prefs: NotificationPrefs = .standard) {
        displayed = prefs
        accepted = prefs
    }

    func replace(_ prefs: NotificationPrefs) {
        displayed = prefs
        accepted = prefs
    }

    func set(
        _ key: WritableKeyPath<NotificationPrefs, Bool>,
        to value: Bool,
        send: @escaping @MainActor (NotificationPrefs) async throws -> Void,
        onFailure: @escaping @MainActor (DomainError) -> Void
    ) {
        displayed[keyPath: key] = value
        edits += 1
        generations[key, default: 0] += 1
        let generation = generations[key]
        let changed = key
        let prior = chain
        chain = Task {
            await prior?.value
            let snapshot = displayed
            do {
                try await send(snapshot)
                accepted = snapshot
            } catch {
                if generations[changed] == generation {
                    displayed[keyPath: changed] = accepted[keyPath: changed]
                }
                onFailure(error as? DomainError ?? .offline)
            }
        }
    }

    func wait() async {
        await chain?.value
    }
}
