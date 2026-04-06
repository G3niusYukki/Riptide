import Foundation
import SwiftUI

/// Manages app localization and language switching for 7 languages.
@MainActor
public final class LocalizationManager: ObservableObject {
    @Published public var currentLanguage: AppLanguage

    private var strings: [String: String] = [:]
    private let defaultsKey = "riptide.language"

    public init() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        if let saved, let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? ""
            if preferred.hasPrefix("zh") {
                self.currentLanguage = .chineseSimplified
            } else {
                self.currentLanguage = .english
            }
        }
        loadStrings()
    }

    /// Changes the app language.
    public func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        loadStrings()

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .languageChanged,
            object: nil,
            userInfo: ["language": language.rawValue]
        )
    }

    /// Get current language (for async contexts).
    public func getCurrentLanguage() -> AppLanguage {
        currentLanguage
    }

    /// Detect and set system language.
    public func setSystemLanguage() {
        let preferred = Locale.preferredLanguages.first ?? ""
        let language: AppLanguage
        if preferred.hasPrefix("zh") {
            language = .chineseSimplified
        } else if preferred.hasPrefix("es") {
            language = .spanish
        } else if preferred.hasPrefix("ru") {
            language = .russian
        } else if preferred.hasPrefix("ja") || preferred.hasPrefix("jp") {
            language = .japanese
        } else if preferred.hasPrefix("ko") {
            language = .korean
        } else if preferred.hasPrefix("fa") {
            language = .persian
        } else {
            language = .english
        }
        setLanguage(language)
    }

    /// All supported languages.
    public func supportedLanguages() -> [AppLanguage] {
        AppLanguage.allCases
    }

    /// Gets the localized string for a key.
    public func string(for key: Localized) -> String {
        strings[key.rawValue] ?? key.rawValue
    }

    /// Gets the localized string for a raw string key.
    public func string(for key: String) -> String {
        strings[key] ?? NSLocalizedString(key, comment: "")
    }

    /// Gets the localized string for a key with format arguments.
    /// Supports both %@ / %d and {key} placeholder styles.
    public func string(for key: Localized, args: CVarArg...) -> String {
        let template = strings[key.rawValue] ?? key.rawValue
        // If template uses %@/%d format specifiers, use String(format:)
        if template.contains("%@") || template.contains("%d") {
            return String(format: template, locale: Locale.current, arguments: args)
        }
        // Otherwise use {name} placeholder replacement
        var result = template
        for (index, arg) in args.enumerated() {
            let placeholder = "{\(index)}"
            result = result.replacingOccurrences(of: placeholder, with: String(describing: arg))
        }
        return result
    }

    // MARK: - Private

    private func loadStrings() {
        // Try to load strings from the selected language's .lproj bundle
        if let path = Bundle.main.path(forResource: currentLanguage.localeIdentifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            for key in Localized.allCases {
                strings[key.rawValue] = bundle.localizedString(
                    forKey: key.rawValue,
                    value: key.rawValue,
                    table: nil
                )
            }
        } else {
            // Fallback: use String Catalog via NSLocalizedString with main bundle
            for key in Localized.allCases {
                strings[key.rawValue] = NSLocalizedString(key.rawValue, comment: "")
            }
        }
    }
}

extension Notification.Name {
    public static let languageChanged = Notification.Name("languageChanged")
}

/// Shared instance for non-SwiftUI code.
public extension LocalizationManager {
    static let shared = LocalizationManager()
}

/// Convenience view modifier for localized text.
public struct LocalizedText: View {
    let key: Localized
    @StateObject private var localization = LocalizationManager()

    public init(_ key: Localized) {
        self.key = key
    }

    public var body: some View {
        Text(localization.string(for: key))
    }
}

/// String extension for localized access via LocalizationManager.
extension String {
    /// Access a localized string using the key, honoring the current language selection.
    public static func localized(_ key: String) -> String {
        guard let languageCode = UserDefaults.standard.string(forKey: "riptide.language"),
              let language = AppLanguage(rawValue: languageCode),
              let bundlePath = Bundle.main.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: bundlePath) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
