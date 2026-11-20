import Foundation
import UIKit

/// The person and sport colors, as values, so the app and the notification extension draw the same
/// avatars. Order matches `SportStyle`: person5, person1, person3, person4, person7, person6, person2.
/// They're the same in dark mode, with ink on them, so the rendered images need no dark versions.
nonisolated enum AvatarPalette {
    nonisolated struct RGB: Sendable {
        var red: Double
        var green: Double
        var blue: Double

        var color: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    }

    /// Pastels, in the same order as the asset catalog names the app used to reference.
    static let people: [RGB] = [
        RGB(red: 1.00, green: 0.612, blue: 0.761), // person5
        RGB(red: 1.00, green: 0.820, blue: 0.361), // person1
        RGB(red: 1.00, green: 0.624, blue: 0.502), // person3
        RGB(red: 0.498, green: 0.847, blue: 0.627), // person4
        RGB(red: 0.949, green: 0.710, blue: 0.420), // person7
        RGB(red: 0.373, green: 0.839, blue: 0.784), // person6
        RGB(red: 0.710, green: 0.612, blue: 0.969), // person2
    ]

    static let ink = RGB(red: 0.122, green: 0.149, blue: 0.220)

    /// A stable palette slot for a person. The same bytes the app sums for `PersonSummary.color`.
    static func index(for id: UUID) -> Int {
        let sum = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(0) { $0 + Int($1) }
        }
        return sum % people.count
    }

    static func person(_ id: UUID) -> RGB {
        people[index(for: id)]
    }

    /// Pin colors. A sport the palette doesn't know gets the neutral.
    static func sport(_ slug: String) -> RGB {
        switch slug {
        case "basketball": RGB(red: 0.949, green: 0.522, blue: 0.227)
        case "tennis": RGB(red: 0.780, green: 0.851, blue: 0.239)
        case "soccer": RGB(red: 0.239, green: 0.698, blue: 0.435)
        case "volleyball": RGB(red: 0.663, green: 0.612, blue: 0.965)
        case "padel": RGB(red: 0.337, green: 0.741, blue: 0.910)
        default: RGB(red: 0.788, green: 0.808, blue: 0.855)
        }
    }

    /// The same emoji `Activity.builtIn` uses, so a notification badge matches the map pin.
    static func emoji(for slug: String) -> String {
        switch slug {
        case "basketball": "🏀"
        case "tennis": "🎾"
        case "soccer": "⚽️"
        case "volleyball": "🏐"
        case "padel": "🏓"
        default: "🏅"
        }
    }
}
