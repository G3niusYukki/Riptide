import Foundation
import SwiftUI

/// Manages app localization and language switching.
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
        // Also support named placeholders like {count}
        for arg in args {
            let value = String(describing: arg)
            let pattern = "\\{\\w+\\}"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result, range: range, withTemplate: value
                )
            }
            break // Only replace first match per arg
        }
        return result
    }

    // MARK: - Private

    private func loadStrings() {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: currentLanguage.rawValue, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            // Fallback: use keys as values
            for key in Localized.allCases {
                strings[key.rawValue] = key.rawValue
            }
            return
        }
        strings = decoded
    }
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

/// Shared instance for non-SwiftUI code.
public extension LocalizationManager {
    static let shared = LocalizationManager()
}
