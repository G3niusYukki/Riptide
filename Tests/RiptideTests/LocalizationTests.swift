import XCTest
@testable import RiptideApp

/// Tests for i18n expansion to 7 languages.
@MainActor
final class LocalizationTests: XCTestCase {

    // MARK: - Language Tests

    func testAllLanguagesHaveDisplayNames() {
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "\(language) should have a display name")
        }
    }

    func testAllLanguagesHaveUniqueRawValues() {
        let rawValues = AppLanguage.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueValues.count, "All language codes should be unique")
    }

    func testLanguageCaseCount() {
        // Should have exactly 7 languages
        XCTAssertEqual(AppLanguage.allCases.count, 7, "Should support 7 languages")
    }

    // MARK: - Localization Manager Tests

    func testLocalizationManagerReturnsCurrentLanguage() {
        let manager = LocalizationManager()
        let language = manager.getCurrentLanguage()
        XCTAssertTrue(AppLanguage.allCases.contains(language), "Current language should be a valid AppLanguage")
    }

    func testLocalizationManagerLanguageSwitch() {
        let manager = LocalizationManager()
        let original = manager.getCurrentLanguage()

        // Switch to Spanish
        manager.setLanguage(.spanish)
        XCTAssertEqual(manager.getCurrentLanguage(), .spanish)

        // Verify it was saved
        let saved = UserDefaults.standard.string(forKey: "riptide.language")
        XCTAssertEqual(saved, "es")

        // Restore original
        manager.setLanguage(original)
    }

    func testLocalizationManagerSystemLanguageDetection() {
        let manager = LocalizationManager()

        // This should not crash and should set a valid language
        manager.setSystemLanguage()
        let language = manager.getCurrentLanguage()
        XCTAssertTrue(AppLanguage.allCases.contains(language))
    }

    func testLocalizationManagerSupportedLanguages() {
        let manager = LocalizationManager()
        let supported = manager.supportedLanguages()
        XCTAssertEqual(supported.count, 7)
        XCTAssertEqual(Set(supported), Set(AppLanguage.allCases))
    }

    // MARK: - Localized Key Tests

    func testAllLocalizedKeysHaveStringValues() {
        let manager = LocalizationManager()

        for key in Localized.allCases {
            let value = manager.string(for: key)
            XCTAssertFalse(value.isEmpty, "Key \(key) should have a localized value")
            // Value should not just be the key itself (indicates missing translation)
            XCTAssertNotEqual(value, key.rawValue, "Key \(key) should have a proper translation, not just the key")
        }
    }

    // MARK: - String Extension Tests

    func testStringLocalizedExtension() {
        let key = "common.save"
        let value = String.localized(key)
        XCTAssertFalse(value.isEmpty)
    }

    // MARK: - Persian (RTL) Tests

    func testPersianLanguageSupport() {
        let persian = AppLanguage.persian
        XCTAssertEqual(persian.rawValue, "fa")
        XCTAssertEqual(persian.displayName, "فارسی")
    }
}
