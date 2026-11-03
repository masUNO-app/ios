import SwiftUI
import UIKit

@main
struct MasUnoApp: App {
    init() {
        // Figma segmented control (Me · Going / Hosting): soft green track, card-white selection.
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(resource: .accentSoft)
        segmented.selectedSegmentTintColor = UIColor(resource: .card)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(resource: .muted)], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(resource: .ink)], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
