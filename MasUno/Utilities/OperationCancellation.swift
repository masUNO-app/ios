import Foundation

/// Cancellation is control flow, not a connection failure. Shared by repository and UI reads.
nonisolated enum OperationCancellation {
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
