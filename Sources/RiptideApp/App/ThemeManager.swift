import Foundation
import SwiftUI
import AppKit

/// Theme manager that persists and applies user theme preferences.
@MainActor
public final class ThemeManager: ObservableObject {
    @Published public private(set) var appearanceMode: AppearanceMode

    public enum AppearanceMode: String, Codable {
        case system
        case light
        case dark
    }

    private let defaultsKey = "riptide.appearanceMode"

    public init() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        self.appearanceMode = AppearanceMode(rawValue: stored ?? "") ?? .system
        applyAppearance()
    }

    /// Sets the appearance mode and persists the choice.
    public func setAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        applyAppearance()
    }

    /// Applies the current appearance mode to the app.
    private func applyAppearance() {
        let appearance: NSAppearance?
        switch appearanceMode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
    }

    /// Returns whether the current effective appearance is dark.
    public var isDark: Bool {
        let effective = NSApp.effectiveAppearance
        let name = effective.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        return name == .darkAqua
    }
}
