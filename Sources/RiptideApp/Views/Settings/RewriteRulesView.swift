import SwiftUI
import Riptide

// MARK: - Rewrite Rules View

/// Manages HTTP rewrite rules (URL-REJECT, URL-REDIRECT, HEADER-MODIFY).
struct RewriteRulesView: View {
    @State private var rules: [RewriteRule] = []
    @State private var showAddSheet = false

    private static let storageKey = "com.riptide.rewriteRules"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("URL 重写规则", systemImage: "pencil.and.list.clipboard")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加规则", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.xmark")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                    Text("暂未配置重写规则")
                        .foregroundStyle(Theme.subtext)
                    Text("添加规则以拦截广告域名或修改请求头")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                ForEach(rules) { rule in
                    RewriteRuleRow(
                        rule: rule,
                        onToggle: { _ in
                            toggleRule(id: rule.id)
                        },
                        onDelete: {
                            removeRule(id: rule.id)
                        }
                    )
                }
            }

            // Info footer
            Text("重写规则仅对 HTTP 明文请求生效。HTTPS 请求需要启用 MITM 拦截后才能应用规则。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            loadRules()
        }
        .sheet(isPresented: $showAddSheet) {
            AddRewriteRuleSheet { newRule in
                rules.append(newRule)
                saveRules()
                showAddSheet = false
            }
            .frame(width: 450, height: 350)
        }
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let loaded = try? JSONDecoder().decode([RewriteRule].self, from: data) {
            rules = loaded
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func toggleRule(id: UUID) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        var updated = rules[idx]
        updated = RewriteRule(id: updated.id, pattern: updated.pattern, action: updated.action, enabled: !updated.enabled)
        rules[idx] = updated
        saveRules()
    }

    private func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }
}

// MARK: - Rewrite Rule Row

struct RewriteRuleRow: View {
    let rule: RewriteRule
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    private var actionLabel: String {
        switch rule.action {
        case .reject: return "拦截"
        case .redirect(let url): return "重定向 → \(url)"
        case .modifyHeader(let key, let value): return "修改请求头 \(key)=\(value)"
        case .modifyResponseHeader(let key, let value): return "修改响应头 \(key)=\(value)"
        }
    }

    private var actionColor: Color {
        switch rule.action {
        case .reject: return Theme.danger
        case .redirect: return Theme.warning
        case .modifyHeader, .modifyResponseHeader: return Theme.accent
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.pattern)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(rule.enabled ? Theme.text : Theme.subtext)
                    if !rule.enabled {
                        Text("(已禁用)")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                Text(actionLabel)
                    .font(.caption2)
                    .foregroundStyle(actionColor)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { onToggle($0) }
            ))

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Add Rewrite Rule Sheet

struct AddRewriteRuleSheet: View {
    let onAdd: (RewriteRule) -> Void

    @State private var pattern = ""
    @State private var actionType: ActionType = .reject
    @State private var headerKey = ""
    @State private var headerValue = ""
    @State private var redirectURL = ""

    enum ActionType: String, CaseIterable {
        case reject = "拦截 (REJECT)"
        case redirect = "重定向 (REDIRECT)"
        case modifyHeader = "修改请求头"
        case modifyResponseHeader = "修改响应头"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("添加重写规则")
                .font(.headline)
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 8) {
                Text("URL 匹配模式:")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                TextField("正则表达式，如 ^https?://.*\\.doubleclick\\.net/.*", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("动作:")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Picker("", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            switch actionType {
            case .modifyHeader, .modifyResponseHeader:
                HStack {
                    TextField("Header 名称", text: $headerKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Header 值", text: $headerValue)
                        .textFieldStyle(.roundedBorder)
                }
            case .redirect:
                TextField("目标 URL", text: $redirectURL)
                    .textFieldStyle(.roundedBorder)
            case .reject:
                EmptyView()
            }

            HStack {
                Spacer()
                Button("添加") {
                    let action: RewriteRule.RewriteAction
                    switch actionType {
                    case .reject: action = .reject
                    case .redirect: action = .redirect(redirectURL)
                    case .modifyHeader: action = .modifyHeader(headerKey, headerValue)
                    case .modifyResponseHeader: action = .modifyResponseHeader(headerKey, headerValue)
                    }
                    onAdd(RewriteRule(pattern: pattern, action: action))
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty)
            }
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
