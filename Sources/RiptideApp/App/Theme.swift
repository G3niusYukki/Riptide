import SwiftUI

enum Theme {
    static let background = Color(hex: "1a1a2e")
    static let backgroundEnd = Color(hex: "16213e")
    static let card = Color.clear  // use .ultraThinMaterial in views
    static let accent = Color(hex: "0fbcf9")
    static let success = Color(hex: "0be881")
    static let danger = Color(hex: "fd7272")
    static let warning = Color(hex: "ffaa00")
    static let text = Color.white
    static let subtext = Color.secondary
    static let cardRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 8

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
