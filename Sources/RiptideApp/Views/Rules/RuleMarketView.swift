import SwiftUI

// MARK: - Rule Market View

/// Browse and import community-maintained rule sets.
struct RuleMarketView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ruleSets: [CommunityRuleSet] = CommunityRuleSet.builtIn
    @State private var importing: Set<String> = []
    @State private var installed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("规则市场", systemImage: "square.grid.3x3.topleft.filled")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("社区维护的规则集，一键导入到当前配置。")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Text("规则集导入后将出现在规则列表的 RULE-SET 条目中。")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Rule set list
            List {
                ForEach(ruleSets) { rs in
                    RuleSetMarketRow(
                        ruleSet: rs,
                        isImporting: importing.contains(rs.id),
                        isInstalled: installed.contains(rs.id),
                        onImport: { importRuleSet(rs) }
                    )
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 480)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func importRuleSet(_ rs: CommunityRuleSet) {
        guard !importing.contains(rs.id) else { return }
        importing.insert(rs.id)

        // Simulate import — in production this would:
        // 1. Download the rule set from rs.url
        // 2. Add a RULE-SET provider to the current profile config
        // 3. Add a RULE-SET entry to the rules list
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // simulated download
            installed.insert(rs.id)
            importing.remove(rs.id)
        }
    }
}

// MARK: - Community Rule Set Model

struct CommunityRuleSet: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: Category
    let behavior: RuleSetBehavior
    let url: String
    let count: Int

    enum Category: String, CaseIterable {
        case privacy = "隐私"
        case routing = "分流"
        case media = "流媒体"

        var icon: String {
            switch self {
            case .privacy: return "shield.slash"
            case .routing: return "arrow.triangle.branch"
            case .media: return "play.tv"
            }
        }
    }

    enum RuleSetBehavior: String {
        case domain = "域名"
        case ipcidr = "IP"
        case classical = "规则"
    }

    static let builtIn: [CommunityRuleSet] = [
        .init(
            id: "reject-ads", name: "广告拦截",
            description: "拦截常见广告与用户追踪域名",
            category: .privacy, behavior: .domain,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/reject-ads.yaml",
            count: 50
        ),
        .init(
            id: "cn-domain", name: "国内直连域名",
            description: "国内常用网站直连，提升访问速度",
            category: .routing, behavior: .domain,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/cn-domain.yaml",
            count: 50
        ),
        .init(
            id: "geoip-cn", name: "国内 IP 直连",
            description: "中国大陆 IP 段直连，基于 GeoLite2 数据库",
            category: .routing, behavior: .ipcidr,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/geoip-cn.yaml",
            count: 8000
        ),
        .init(
            id: "apple-services", name: "Apple 服务分流",
            description: "优化 Apple 服务在中国大陆的连接",
            category: .routing, behavior: .domain,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/apple-services.yaml",
            count: 38
        ),
        .init(
            id: "openai", name: "AI 服务",
            description: "OpenAI, Claude, Gemini 等 AI 服务域名",
            category: .routing, behavior: .domain,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/ai-services.yaml",
            count: 15
        ),
        .init(
            id: "streaming-us", name: "美国流媒体",
            description: "Netflix, Disney+, HBO Max, Hulu, YouTube",
            category: .media, behavior: .domain,
            url: "https://raw.githubusercontent.com/riptide/riptide-rules/main/streaming-us.yaml",
            count: 25
        ),
    ]
}

// MARK: - Rule Set Market Row

struct RuleSetMarketRow: View {
    let ruleSet: CommunityRuleSet
    let isImporting: Bool
    let isInstalled: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ruleSet.category.icon)
                .font(.title3)
                .foregroundStyle(categoryColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ruleSet.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)

                    Badge(ruleSet.behavior.rawValue)
                    Badge(ruleSet.category.rawValue)
                }

                Text(ruleSet.description)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)

                Text("约 \(ruleSet.count) 条规则")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }

            Spacer()

            if isInstalled {
                Label("已导入", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.success)
            } else if isImporting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20)
            } else {
                Button("导入", action: onImport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryColor: Color {
        switch ruleSet.category {
        case .privacy: return Theme.danger
        case .routing: return Theme.accent
        case .media: return Theme.warning
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .foregroundStyle(Theme.subtext)
    }
}
