import Foundation

// MARK: - TransportError + LocalizedError

extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noSessionAvailable:
            return "无可用传输会话"
        case .unsupportedSessionOperation(let detail):
            return "不支持的会话操作: \(detail)"
        case .dialFailed(let reason):
            return "连接失败: \(reason)"
        case .sendFailed(let reason):
            return "发送数据失败: \(reason)"
        case .receiveFailed(let reason):
            return "接收数据失败: \(reason)"
        case .connectionFailed(let reason):
            return "连接已断开: \(reason)"
        case .cancelled:
            return "传输已取消"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noSessionAvailable, .connectionFailed:
            return "请检查网络连接和代理节点是否可用"
        case .dialFailed:
            return "请检查目标地址是否正确，或尝试其他节点"
        case .cancelled:
            return nil
        default:
            return "请稍后重试"
        }
    }
}

// MARK: - RuntimeError + LocalizedError

extension RuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return "Helper 工具未安装"
        case .configGenerationFailed(let reason):
            return "配置生成失败: \(reason)"
        case .launchFailed(let reason):
            return "mihomo 启动失败: \(reason)"
        case .apiNotAvailable:
            return "mihomo API 不可用"
        case .alreadyRunning:
            return "mihomo 已在运行中"
        case .notRunning:
            return "mihomo 未运行"
        case .tunUnavailable(let reason):
            return "TUN 模式不可用: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .helperNotInstalled:
            return "请在设置中安装 Helper 工具"
        case .launchFailed:
            return "请检查配置文件是否正确，或重新安装 mihomo"
        case .apiNotAvailable:
            return "请等待 mihomo 完全启动后重试"
        case .alreadyRunning:
            return "请先停止当前运行的实例"
        case .notRunning:
            return "请先启动 mihomo"
        case .tunUnavailable:
            return "请使用系统代理模式，或检查 Helper 安装状态"
        default:
            return "请尝试重启 mihomo"
        }
    }
}

// MARK: - CoreManagerError + LocalizedError

extension CoreManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            return "mihomo 下载失败: \(reason)"
        case .binaryNotFound:
            return "mihomo 二进制文件未找到"
        case .setupFailed(let reason):
            return "mihomo 安装失败: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .downloadFailed:
            return "请检查网络连接后重试"
        case .binaryNotFound:
            return "请重新下载 mihomo"
        case .setupFailed:
            return "请检查文件权限后重试"
        }
    }
}

// MARK: - MihomoAPIError + LocalizedError

extension MihomoAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .networkError(let reason):
            return "网络请求失败: \(reason)"
        case .decodingError(let reason):
            return "响应解析失败: \(reason)"
        case .apiError(let code, let msg):
            return "API 错误 (\(code)): \(msg)"
        case .proxyNotFound(let name):
            return "代理节点未找到: \(name)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "请检查 mihomo 是否正在运行"
        case .proxyNotFound:
            return "请检查节点名称是否正确"
        default:
            return nil
        }
    }
}

// MARK: - ClashConfigError + LocalizedError

extension ClashConfigError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let detail):
            return "YAML 格式错误: \(detail)"
        case .unsupportedMode(let mode):
            return "不支持的模式: \(mode)"
        case .missingProxies:
            return "配置中缺少 proxies 字段"
        case .missingRules:
            return "配置中缺少 rules 字段"
        case .invalidProxy(let idx, let reason):
            return "代理节点 #\(idx + 1) 配置无效: \(reason)"
        case .invalidRule(let idx, let reason):
            return "规则 #\(idx + 1) 配置无效: \(reason)"
        case .unknownProxyReference(let name):
            return "引用了不存在的代理: \(name)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidYAML:
            return "请检查 YAML 语法是否正确"
        case .missingProxies, .missingRules:
            return "请确保配置文件包含完整的 proxies 和 rules 字段"
        case .unknownProxyReference:
            return "请检查规则中引用的代理名称是否在 proxies 中定义"
        default:
            return "请检查配置文件格式"
        }
    }
}

// MARK: - ProfileStoreError + LocalizedError

extension ProfileStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "配置文件未找到 (ID: \(id.uuidString.prefix(8)))"
        case .parseFailed(let reason):
            return "配置解析失败: \(reason)"
        case .persistenceFailed(let reason):
            return "配置保存失败: \(reason)"
        case .refreshFailed(_, let reason):
            return "订阅刷新失败: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "请重新导入配置文件"
        case .persistenceFailed:
            return "请检查磁盘空间和文件权限"
        case .refreshFailed:
            return "请检查订阅 URL 是否有效"
        default:
            return nil
        }
    }
}

// MARK: - SubscriptionError + LocalizedError

extension SubscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "订阅 URL 无效"
        case .fetchFailed(let reason):
            return "订阅获取失败: \(reason)"
        case .parseFailed(let reason):
            return "订阅解析失败: \(reason)"
        case .noNodes:
            return "订阅中未包含任何节点"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "请检查订阅地址格式是否正确"
        case .fetchFailed:
            return "请检查网络连接和订阅地址是否有效"
        case .noNodes:
            return "请确认订阅源是否正常"
        default:
            return nil
        }
    }
}

// MARK: - SystemProxyError + LocalizedError

extension SystemProxyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyEnabled:
            return "系统代理已启用"
        case .notEnabled:
            return "系统代理未启用"
        case .portInUse(let port):
            return "端口 \(port) 已被占用"
        case .permissionDenied:
            return "权限不足，无法修改系统代理"
        case .unknown(let reason):
            return "系统代理错误: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .alreadyEnabled:
            return "请先禁用当前代理再重新启用"
        case .notEnabled:
            return "代理当前未启用"
        case .portInUse:
            return "请关闭占用该端口的程序，或更换端口"
        case .permissionDenied:
            return "请确保 Helper 工具已正确安装"
        default:
            return nil
        }
    }
}

// MARK: - VPNManagerError + LocalizedError

extension VPNManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "VPN 未配置"
        case .settingsFailed(let reason):
            return "VPN 设置失败: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            return "请先配置 VPN 参数"
        case .settingsFailed:
            return "请检查 Helper 工具是否已安装"
        }
    }
}

// MARK: - AppGroupStateStoreError + LocalizedError

extension AppGroupStateStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "状态数据编码失败"
        case .decodingFailed(let reason):
            return "状态数据解码失败: \(reason)"
        case .writeFailed(let reason):
            return "状态数据写入失败: \(reason)"
        }
    }
}

// MARK: - NodeValidationError + LocalizedError

extension NodeValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .validationFailed(let reasons):
            return "节点验证失败: \(reasons.joined(separator: "; "))"
        case .invalidProxyKind:
            return "不支持的代理类型"
        case .storeError(let reason):
            return "节点存储错误: \(reason)"
        }
    }
}
