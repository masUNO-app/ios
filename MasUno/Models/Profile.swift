import Foundation

/// The signed-in student, as shown on the Me card.
struct Profile: Hashable {
    var firstName: String
    var lastName: String
    var classYear: Int
    var school: String
    var isVerified: Bool
    var interests: [Sport]

    var fullName: String { "\(firstName) \(lastName)" }
}
