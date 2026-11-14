import Foundation
import StoreKit

/// Where this install came from, for the beta tester badge (N37).
enum BuildChannel {
    /// True only for a TestFlight install. Debug builds and the simulator never are, so running from
    /// Xcode can't stamp the badge. Otherwise StoreKit's signed `AppTransaction` says which App Store
    /// environment issued the install: TestFlight installs are `.sandbox`, App Store ones `.production`.
    /// If the transaction can't be read (no network on first launch, say), the receipt's file name is
    /// the older tell: TestFlight writes `sandboxReceipt`. The answer is self-reported to the server,
    /// which is fine for a badge that grants nothing.
    ///
    /// DEBUG only: `-betaTester YES` forces it on, to review the badge on the mock backend.
    static var isTestFlight: Bool {
        get async {
            #if DEBUG
            return UserDefaults.standard.bool(forKey: "betaTester")
            #elseif targetEnvironment(simulator)
            return false
            #else
            if let result = try? await AppTransaction.shared, case .verified(let transaction) = result {
                return transaction.environment == .sandbox
            }
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            #endif
        }
    }
}
