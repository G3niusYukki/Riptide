import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
public final class ThemeManager {
    public private(set) var appearanceMode: AppearanceMode

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

    public func setAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        applyAppearance()
    }

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

    public var isDark: Bool {
        let effective = NSApp.effectiveAppearance
        let name = effective.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        return name == .darkAqua
    }
}
