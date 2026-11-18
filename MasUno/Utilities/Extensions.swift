import UIKit

extension Set {
    /// Adds the element, or removes it when it's already there: a sport chip's tap.
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

extension UIApplication {
    /// This app's page in iPhone Settings (location, notifications).
    static var openSettingsURL: URL { URL(string: openSettingsURLString)! }
}
