import SwiftUI
import UIKit

@main
struct MasUnoApp: App {
    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
