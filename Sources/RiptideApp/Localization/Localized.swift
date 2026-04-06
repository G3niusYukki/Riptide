import Foundation

/// All localizable string keys used in the app.
/// Each case maps to a key in the Localizable.xcstrings file.
public enum Localized: String, CaseIterable {
    // MARK: - Tab Names
    case tabConfig = "tab.config"
    case tabProxy = "tab.proxy"
    case tabTraffic = "tab.traffic"
    case tabRules = "tab.rules"
    case tabLogs = "tab.logs"

    // MARK: - Config Tab
    case configMode = "config.mode"
    case configSystemProxy = "config.system_proxy"
    case configTunMode = "config.tun_mode"
    case configImport = "config.import"
    case configProfiles = "config.profiles"
    case configSubscriptions = "config.subscriptions"
    case configNoSubscriptions = "config.no_subscriptions"
    case configAddSubscriptionHint = "config.add_subscription_hint"
    case configHelperInstalled = "config.helper_installed"
    case configHelperNotInstalled = "config.helper_not_installed"
    case configInstallHelper = "config.install_helper"
    case configInstallHelperHint = "config.install_helper_hint"
    case configModeLocked = "config.mode_locked"

    // MARK: - Profile
    case profileActive = "profile.active"
    case profileActivate = "profile.activate"
    case profileDelete = "profile.delete"
    case profileEdit = "profile.edit"
    case profileNodes = "profile.nodes"
    case profileRules = "profile.rules"
    case configAllConfigs = "config.all_configs"

    // MARK: - Subscription
    case subAdd = "subscription.add"
    case subEdit = "subscription.edit"
    case subUpdate = "subscription.update"
    case subUpdating = "subscription.updating"
    case subNeverUpdated = "subscription.never_updated"
    case subError = "subscription.error"
    case subConfigs = "subscription.configs"
    case subName = "subscription.name"
    case subUrl = "subscription.url"
    case subAutoUpdate = "subscription.auto_update"
    case subUpdateInterval = "subscription.update_interval"
    case subInterval15m = "subscription.interval_15m"
    case subInterval30m = "subscription.interval_30m"
    case subInterval1h = "subscription.interval_1h"
    case subInterval6h = "subscription.interval_6h"
    case subInterval24h = "subscription.interval_24h"

    // MARK: - Proxy Tab
    case proxyDelayTest = "proxy.delay_test"
    case proxyDirect = "proxy.direct"
    case proxyTimeout = "proxy.timeout"

    // MARK: - Traffic Tab
    case trafficUpload = "traffic.upload"
    case trafficDownload = "traffic.download"
    case trafficActiveConnections = "traffic.active_connections"
    case trafficNoConnections = "traffic.no_connections"

    // MARK: - Connection List
    case connSearch = "connection.search"
    case connCloseAll = "connection.close_all"
    case connClosing = "connection.closing"
    case connNoConnections = "connection.no_connections"

    // MARK: - Logs Tab
    case logsClear = "logs.clear"
    case logsExport = "logs.export"
    case logsNoLogs = "logs.no_logs"
    case logsSearch = "logs.search"
    case logsLevel = "logs.level"
    case logsAll = "logs.all"

    // MARK: - Rules Tab
    case rulesList = "rules.list"
    case rulesTotal = "rules.total"
    case rulesDirect = "rules.direct"
    case rulesProxy = "rules.proxy"
    case rulesReject = "rules.reject"

    // MARK: - MITM Settings
    case mitmTitle = "mitm.title"
    case mitmEnable = "mitm.enable"
    case mitmHosts = "mitm.hosts"
    case mitmExcludeHosts = "mitm.exclude_hosts"
    case mitmInstallCert = "mitm.install_cert"
    case mitmCertInstalled = "mitm.cert_installed"
    case mitmCertNotInstalled = "mitm.cert_not_installed"
    case mitmLog = "mitm.log"
    case mitmAll = "mitm.all"

    // MARK: - Menu Bar
    case menuStart = "menu.start"
    case menuStop = "menu.stop"
    case menuOpenPanel = "menu.open_panel"
    case menuQuit = "menu.quit"
    case menuMode = "menu.mode"
    case menuConfigs = "menu.configs"
    case menuConnected = "menu.connected"
    case menuDisconnected = "menu.disconnected"
    case menuSwitchModeFirst = "menu.switch_mode_first"

    // MARK: - Language
    case languageSelect = "language.select"
    case languageAuto = "language.auto"

    // MARK: - Common
    case commonCancel = "common.cancel"
    case commonConfirm = "common.confirm"
    case commonAdd = "common.add"
    case commonSave = "common.save"
    case commonDelete = "common.delete"
    case commonEdit = "common.edit"
    case commonClose = "common.close"
    case commonLoading = "common.loading"
    case commonError = "common.error"
    case commonUnknown = "common.unknown"

    /// Get the localized string value for this key.
    public var string: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

/// Extended language codes supported by the app (7 languages total).
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case chineseSimplified = "zh-Hans"
    case english = "en"
    case spanish = "es"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case persian = "fa"

    public var id: String { rawValue }

    /// Display name in the language itself.
    public var displayName: String {
        switch self {
        case .chineseSimplified: return "简体中文"
        case .english: return "English"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .persian: return "فارسی"
        }
    }

    /// Locale identifier for this language.
    public var localeIdentifier: String {
        rawValue
    }
}
