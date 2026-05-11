import SwiftUI
import UniformTypeIdentifiers
import Riptide

// MARK: - Config Merge View

public struct ConfigMergeView: View {
    @State private var viewModel: ConfigMergeViewModel
    @State private var showFilePicker = false
    @State private var showManualInput = false
    @State private var manualYAML = ""
    @State private var manualName = ""

    public init(viewModel: ConfigMergeViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("配置合并")
                    .font(.headline)
                Spacer()
                Button("添加文件") {
                    showFilePicker = true
                }
                .buttonStyle(.bordered)

                Button("手动输入") {
                    manualName = ""
                    manualYAML = ""
                    showManualInput = true
                }
                .buttonStyle(.bordered)
            }
            .padding()

            ScrollView {
                VStack(spacing: 16) {
                    // Current profile info
                    if let config = viewModel.currentConfig {
                        currentConfigCard(config)
                    }

                    // Merge sources
                    mergeSourcesSection

                    // Action buttons
                    if !viewModel.mergeSources.isEmpty {
                        actionButtons
                    }

                    // Preview
                    if let preview = viewModel.previewResult {
                        previewSection(preview)
                    }

                    // Error
                    if let error = viewModel.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "yaml")!, UTType(filenameExtension: "yml")!],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    viewModel.addFileSource(url: url)
                }
            }
        }
        .sheet(isPresented: $showManualInput) {
            manualInputSheet
        }
        .task {
            await viewModel.loadCurrentProfile()
        }
    }

    // MARK: - Current Config Card

    private func currentConfigCard(_ config: RiptideConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前配置")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("\(config.proxies.count) 节点", systemImage: "server.rack")
                Label("\(config.rules.count) 规则", systemImage: "list.bullet")
                Label("\(config.proxyGroups.count) 组", systemImage: "rectangle.3.group")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Merge Sources

    private var mergeSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("合并源")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.mergeSources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("添加 YAML 文件作为合并源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(viewModel.mergeSources) { source in
                    HStack {
                        Image(systemName: sourceIcon(source.kind))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading) {
                            Text(source.name)
                                .font(.body)
                            Text(sourceDescription(source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.removeSource(source)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .onDelete { offsets in
                    viewModel.removeSource(at: offsets)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button("预览合并结果") {
                viewModel.generatePreview()
            }
            .buttonStyle(.borderedProminent)

            if viewModel.previewResult != nil {
                Button("应用合并") {
                    Task {
                        try? await viewModel.applyMerge()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.isMerging)
            }
        }
    }

    // MARK: - Preview Section

    private func previewSection(_ preview: MergePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("合并预览")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let diff = preview.diff

            // Diff summary
            VStack(alignment: .leading, spacing: 6) {
                if !diff.addedProxies.isEmpty {
                    Label("+\(diff.addedProxies.count) 新增节点: \(diff.addedProxies.joined(separator: ", "))",
                          systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if !diff.removedProxies.isEmpty {
                    Label("-\(diff.removedProxies.count) 移除节点: \(diff.removedProxies.joined(separator: ", "))",
                          systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !diff.modifiedProxies.isEmpty {
                    Label("~\(diff.modifiedProxies.count) 修改节点: \(diff.modifiedProxies.joined(separator: ", "))",
                          systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if diff.addedRules > 0 {
                    Label("+\(diff.addedRules) 新增规则", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if !diff.hasChanges {
                    Label("无变更", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Totals
            HStack(spacing: 16) {
                Text("合并后: \(diff.totalProxies) 节点")
                Text("\(diff.totalRules) 规则")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Manual Input Sheet

    private var manualInputSheet: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("合并源名称", text: $manualName)
                }

                Section("YAML 内容") {
                    TextEditor(text: $manualYAML)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("手动输入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showManualInput = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let name = manualName.isEmpty ? "手动输入" : manualName
                        viewModel.addYAMLSource(name: name, yaml: manualYAML)
                        showManualInput = false
                    }
                    .disabled(manualYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    // MARK: - Helpers

    private func sourceIcon(_ kind: MergeSourceKind) -> String {
        switch kind {
        case .file: return "doc"
        case .url: return "cloud"
        case .manual: return "keyboard"
        }
    }

    private func sourceDescription(_ source: MergeSource) -> String {
        switch source.kind {
        case .file(let url): return url.lastPathComponent
        case .url(let url): return url.absoluteString
        case .manual: return "手动输入"
        }
    }
}
