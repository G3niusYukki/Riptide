import Foundation
import SwiftUI

/// Manages app localization and language switching.
@MainActor
public final class LocalizationManager: ObservableObject {
    @Published public var currentLanguage: AppLanguage

    private var strings: [String: String] = [:]
    private let defaultsKey = "riptide.language"

    public init() {
        // Load saved language preference
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        if let saved, let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Default to system language
            let preferred = Locale.preferredLanguages.first ?? ""
            if preferred.hasPrefix("zh") {
                self.currentLanguage = .zhHans
            } else {
                self.currentLanguage = .en
            }
        }
        loadStrings()
    }

    /// Changes the app language.
    public func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        loadStrings()
    }

    /// Gets the localized string for a key.
    public func string(for key: Localized) -> String {
        strings[key.rawValue] ?? key.rawValue
    }

    /// Gets the localized string for a key with format arguments.
    public func string(for key: Localized, args: CVarArg...) -> String {
        let format = strings[key.rawValue] ?? key.rawValue
        return String(format: format, locale: Locale.current, arguments: args)
    }

    // MARK: - Private

    private func loadStrings() {
        guard let url = Bundle.main.url(forResource: currentLanguage.rawValue, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            // Fallback: try loading from Resources directory
            loadFromResourcesDirectory()
            return
        }
        strings = decoded
    }

    private func loadFromResourcesDirectory() {
        // Try loading from the Resources directory (for development)
        let resourceURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(currentLanguage.rawValue).json")

        guard let data = try? Data(contentsOf: resourceURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            // Final fallback: use keys as values
            for key in Localized.allCases {
                strings[key.rawValue] = key.rawValue
            }
            return
        }
        strings = decoded
    }
}

/// Convenience extension for View to access localization.
extension View {
    /// Returns the localized string for the given key using the app's LocalizationManager.
    /// Note: In production, inject LocalizationManager via environment.
    public func localized(_ key: Localized) -> String {
        // Direct file fallback — in production use @EnvironmentObject
        return LocalizationManager.shared?.string(for: key) ?? key.rawValue
    }
}

/// Shared instance for convenience access.
public extension LocalizationManager {
    static let shared: LocalizationManager? = {
        let manager = LocalizationManager()
        return manager
    }()
}
