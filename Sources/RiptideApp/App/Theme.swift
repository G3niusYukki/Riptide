import SwiftUI
import AppKit

/// App theme colors. Adapts to light/dark mode via `colorScheme`.
enum Theme {
    // Fixed accent colors (work in both light and dark modes)
    static let accent = Color(hex: "0fbcf9")
    static let success = Color(hex: "0be881")
    static let danger = Color(hex: "fd7272")
    static let warning = Color(hex: "ffaa00")
    static let background = Color(hex: "1a1a2e")        // dark background, legacy
    static let backgroundEnd = Color(hex: "16213e")      // dark gradient end, legacy
    static let cardRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 8

    // Semantic colors — auto-adapt to color scheme
    static let text = Color.primary
    static let subtext = Color.secondary
    static let card = Color.clear  // use .ultraThinMaterial in views

    /// Background gradient that adapts to the current color scheme.
    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            return LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color(hex: "f0f2f5"), Color(hex: "e8ecf1")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        @unknown default:
            return LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Legacy gradient. Auto-detects dark/light from the current window / system setting.
    static var backgroundGradient: LinearGradient {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return backgroundGradient(for: isDark ? .dark : .light)
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
