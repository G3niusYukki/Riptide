import SwiftUI
import Riptide

/// Basic YAML editor for a profile by id.
///
/// Provides a monospaced text area for editing the raw YAML, with a
/// "validate" button that round-trips through `ClashConfigParser`. "Save"
/// is only enabled once the YAML parses cleanly. Syntax highlighting is
/// intentionally minimal (the placeholder caption in the header notes that
/// field-level highlighting is a future enhancement).
struct YAMLEditorView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// Id of the profile being edited (matches `AppViewModel.Profile.id`).
    let profileID: UUID

    @State private var yamlText: String = ""
    @State private var initialYAML: String = ""
    @State private var validationError: String?
    @State private var isValidating = false
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑 YAML")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(A11yID.Config.yamlEditorClose)
            }

            Text("高级功能: YAML 语法高亮、字段级编辑等为未来工作。当前为基本文本编辑+保存前验证。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            TextEditor(text: $yamlText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 400)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            validationError != nil ? Theme.danger : Theme.subtext.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .accessibilityIdentifier(A11yID.Config.yamlEditorText)

            if let error = validationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier(A11yID.Config.yamlEditorError)
            } else if yamlText != initialYAML {
                Label("内容已修改,尚未验证", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            HStack {
                Button {
                    validate()
                } label: {
                    Label(isValidating ? "验证中…" : "验证", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .disabled(isValidating)
                .accessibilityIdentifier(A11yID.Config.yamlEditorValidate)

                Button {
                    save()
                } label: {
                    Label(isSaving ? "保存中…" : "保存", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationError != nil || isSaving || yamlText == initialYAML)
                .accessibilityIdentifier(A11yID.Config.yamlEditorSave)

                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .onAppear { loadCurrentYAML() }
    }

    // MARK: - Actions

    private func loadCurrentYAML() {
        Task {
            let text = await vm.profileYAML(id: profileID)
            await MainActor.run {
                initialYAML = text
                yamlText = text
                validationError = nil
            }
        }
    }

    private func validate() {
        isValidating = true
        defer { isValidating = false }
        do {
            _ = try ClashConfigParser.parse(yaml: yamlText)
            validationError = nil
        } catch {
            validationError = "YAML 解析失败: \(error.localizedDescription)"
        }
    }

    private func save() {
        // Re-validate right before saving to avoid racing the user.
        validate()
        guard validationError == nil else { return }
        isSaving = true
        Task {
            defer { Task { @MainActor in isSaving = false } }
            do {
                try await vm.updateProfileYAML(profileID, yaml: yamlText)
                dismiss()
            } catch {
                await MainActor.run {
                    validationError = "保存失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
