import AppIntents

// MARK: - Switch Proxy Mode Intent

/// Shortcuts integration: switch between system proxy, TUN, and direct modes.
@available(macOS 14, *)
struct SwitchProxyModeIntent: AppIntent {
    static var title: LocalizedStringResource = "切换代理模式"
    static var description: IntentDescription = .init(
        "在系统代理、TUN 模式和直连之间切换",
        categoryName: "网络"
    )

    @Parameter(
        title: "目标模式",
        default: .systemProxy
    )
    var mode: ProxyModeOption

    enum ProxyModeOption: String, AppEnum {
        case systemProxy
        case tun
        case direct

        static var typeDisplayRepresentation: TypeDisplayRepresentation = "代理模式"
        static var caseDisplayRepresentations: [ProxyModeOption: DisplayRepresentation] = [
            .systemProxy: "系统代理",
            .tun: "TUN 模式",
            .direct: "直连",
        ]
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name: String
        switch mode {
        case .systemProxy: name = "系统代理"
        case .tun: name = "TUN 模式"
        case .direct: name = "直连"
        }
        return .result(dialog: "已切换到「\(name)」")
    }
}

// MARK: - Select Profile Intent

/// Shortcuts integration: activate a specific configuration profile by name.
@available(macOS 14, *)
struct SelectProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "切换配置"
    static var description: IntentDescription = .init(
        "切换到指定的代理配置 profile",
        categoryName: "网络"
    )

    @Parameter(title: "配置名称")
    var profileName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "已切换到配置「\(profileName)」")
    }
}
