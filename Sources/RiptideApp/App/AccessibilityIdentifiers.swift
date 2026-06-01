import Foundation

/// 集中定义所有 UI 测试可访问性标识符。
/// 视图代码通过 `.accessibilityIdentifier(...)` 引用这些常量。
public enum A11yID {
    public enum Tab {
        public static let dashboard = "tab.dashboard"
        public static let config = "tab.config"
        public static let proxy = "tab.proxy"
        public static let traffic = "tab.traffic"
        public static let logs = "tab.logs"
    }

    public enum Dashboard {
        public static let modeCard = "dashboard.mode-card"
        public static let nodeCard = "dashboard.node-card"
        public static let speedCard = "dashboard.speed-card"
        public static let diagnosticsButton = "dashboard.diagnostics-button"
    }

    public enum Config {
        public static let importButton = "config.import-button"
        public static let addSubscription = "config.add-subscription"
        public static let mergeButton = "config.merge-button"
    }

    public enum Proxy {
        public static let groupCard = "proxy.group-card"
        public static let testDelayButton = "proxy.test-delay-button"
        public static let nodeRow = "proxy.node-row"
    }

    public enum Traffic {
        public static let chart = "traffic.chart"
        public static let connectionRow = "traffic.connection-row"
        public static let connectionDetailToggle = "traffic.connection-detail-toggle"
    }

    public enum Logs {
        public static let levelFilter = "logs.level-filter"
        public static let searchField = "logs.search-field"
        public static let exportButton = "logs.export-button"
    }
}
