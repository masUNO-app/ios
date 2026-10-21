import SwiftUI

/// Colors pulled from the Figma frames (plusone-figma, Page 1).
enum Theme {
    // Plans screens (Registered / Hosted)
    static let cream = Color(hex: 0xF8F1E7)
    static let card = Color(hex: 0xFFFCF7)
    static let cardStroke = Color(hex: 0xEDE2D3)
    static let ink = Color(hex: 0x2A1E14)
    static let secondaryInk = Color(hex: 0x7A6A5C)
    static let orange = Color(hex: 0xE5791E)
    static let orangeSoft = Color(hex: 0xF8DFC2)
    static let chatBackground = Color(hex: 0xF3E8DA)
    static let tan = Color(hex: 0xF2E2BC)
    static let tanStroke = Color(hex: 0xD9BE7E)

    // Map screens
    static let pinBlue = Color(hex: 0x3D9BF0)
    static let actionBlue = Color(hex: 0x0A84FF)
    static let youRed = Color(hex: 0xF0453A)
    static let mapWarmth = Color(hex: 0xF6E7D2).opacity(0.18)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
