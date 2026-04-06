import SwiftUI

/// Language selection view with support for 7 languages.
struct LanguageSelectorView: View {
    @State private var selectedLanguage: AppLanguage = .english
    @State private var isAutoDetect = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager()

    var body: some View {
        NavigationStack {
            List {
                autoDetectSection
                languageSection
            }
            .navigationTitle(String.localized("language.select"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String.localized("common.save")) {
                        saveAndDismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.localized("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadCurrentLanguage()
        }
    }

    private var autoDetectSection: some View {
        Section {
            Button {
                setAutoDetect()
            } label: {
                HStack {
                    Text(String.localized("language.auto"))
                    Spacer()
                    if isAutoDetect {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var languageSection: some View {
        Section(String.localized("language.select")) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    setLanguage(language)
                } label: {
                    HStack {
                        Text(language.displayName)
                        Spacer()
                        if selectedLanguage == language && !isAutoDetect {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadCurrentLanguage() {
        selectedLanguage = localization.getCurrentLanguage()
        // Check if using auto-detect (no saved preference)
        isAutoDetect = UserDefaults.standard.string(forKey: "riptide.language") == nil
    }

    private func setLanguage(_ language: AppLanguage) {
        localization.setLanguage(language)
        selectedLanguage = language
        isAutoDetect = false
    }

    private func setAutoDetect() {
        UserDefaults.standard.removeObject(forKey: "riptide.language")
        localization.setSystemLanguage()
        selectedLanguage = localization.getCurrentLanguage()
        isAutoDetect = true
    }

    private func saveAndDismiss() {
        dismiss()
    }
}

#Preview {
    LanguageSelectorView()
}
