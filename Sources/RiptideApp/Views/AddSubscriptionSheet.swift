import SwiftUI

/// Sheet for adding or editing a subscription.
struct AddSubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: AppViewModel

    // Editing mode
    let editingSubscription: SubscriptionDisplay?

    // Form state
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var autoUpdate: Bool = true
    @State private var updateInterval: Double = 3600 // 1 hour
    @State private var isUpdating = false
    @State private var isFetching = false
    @State private var fetchError: String?

    init(vm: AppViewModel, editing: SubscriptionDisplay? = nil) {
        self.vm = vm
        self.editingSubscription = editing
        if let editing {
            _name = State(initialValue: editing.name)
            _url = State(initialValue: editing.url)
            _autoUpdate = State(initialValue: editing.autoUpdate)
            _updateInterval = State(initialValue: 3600) // default
        }
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("订阅 URL (https://...)", text: $url)
                        .textFieldStyle(.roundedBorder)
                }

                Section("自动更新") {
                    Toggle("启用自动更新", isOn: $autoUpdate)

                    if autoUpdate {
                        Picker("更新间隔", selection: $updateInterval) {
                            Text("15 分钟").tag(900.0)
                            Text("30 分钟").tag(1800.0)
                            Text("1 小时").tag(3600.0)
                            Text("6 小时").tag(21600.0)
                            Text("24 小时").tag(86400.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let error = fetchError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingSubscription != nil ? "编辑订阅" : "添加订阅")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editingSubscription != nil {
                        Button("保存") {
                            saveEditing()
                        }
                        .disabled(!isFormValid || isUpdating)
                    } else {
                        Button("添加") {
                            addSubscription()
                        }
                        .disabled(!isFormValid || isFetching)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func addSubscription() {
        guard let subURL = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            fetchError = "无效的 URL"
            return
        }
        isFetching = true
        fetchError = nil
        Task {
            await vm.addSubscription(
                url: subURL.absoluteString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                autoUpdate: autoUpdate,
                interval: updateInterval
            )
            await MainActor.run {
                isFetching = false
                if vm.lastError == nil {
                    dismiss()
                } else {
                    fetchError = vm.lastError
                }
            }
        }
    }

    private func saveEditing() {
        guard let editing = editingSubscription else { return }
        isUpdating = true
        Task {
            await vm.editSubscription(
                id: editing.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                autoUpdate: autoUpdate,
                interval: updateInterval
            )
            await MainActor.run {
                isUpdating = false
                dismiss()
            }
        }
    }
}
