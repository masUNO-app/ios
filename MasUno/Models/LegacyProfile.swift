import Foundation

/// The mock Me card the screens still use. Replaced by `Profile` when they move to the
/// E1 models (E24); delete this file then.
struct LegacyProfile: Hashable {
    var firstName: String
    var lastName: String
    var classYear: Int
    var school: String
    var isVerified: Bool
    var interests: [Sport]

    var fullName: String { "\(firstName) \(lastName)" }
}
