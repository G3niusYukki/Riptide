import Foundation

/// Unified error type for the Riptide library.
///
/// Wraps subsystem-specific errors into a single type for consistent
/// error handling, presentation, and logging across the application.
///
/// Subsystems retain their own fine-grained error enums; `RiptideError`
/// provides a top-level layer for cross-cutting concerns.
public enum RiptideError: Error, LocalizedError, Sendable {

    // MARK: - Config Layer

    /// Clash YAML config parsing error.
    case config(ClashConfigError)
    /// Config sync (WebDAV) error.
    case configSync(ConfigSyncError)
    /// Config deep-merge error.
    case configMerge(ConfigMerger.MergeError)

    // MARK: - Transport Layer

    /// Transport session error (TCP/TLS/WS/QUIC/HTTP2).
    case transport(TransportError)
    /// Proxy group resolution error.
    case proxyGroup(ProxyGroupResolverError)

    // MARK: - Protocol Layer

    /// Outbound protocol framing error (SS/VMess/VLESS/Trojan/etc).
    case protocolOutbound(ProtocolError)

    // MARK: - Runtime

    /// Mihomo runtime manager error.
    case runtime(RuntimeError)
    /// Mihomo core manager error.
    case core(CoreManagerError)
    /// Mihomo REST API error.
    case api(MihomoAPIError)
    /// Mihomo binary download error.
    case download(DownloadError)

    // MARK: - VPN / TUN

    /// VPN tunnel manager error.
    case vpn(VPNManagerError)
    /// Tunnel routing engine error.
    case tunnelRouting(TUNRoutingEngineError)
    /// Generic tunnel error.
    case tunnel(TunnelError)

    // MARK: - XPC

    /// Helper tool protocol error.
    case xpc(HelperToolError)
    /// XPC connection error.
    case xpcConnection(HelperToolConnection.ConnectionError)

    // MARK: - App Layer

    /// Profile persistence error.
    case profile(ProfileStoreError)
    /// Subscription management error.
    case subscription(SubscriptionError)
    /// System proxy control error.
    case systemProxy(SystemProxyError)
    /// Keychain / secure storage error.
    case keychain(KeychainError)

    // MARK: - Generic

    /// Wraps an arbitrary error with contextual description.
    case underlying(any Error & Sendable, context: String)
    /// Operation timed out.
    case timeout(operation: String, duration: TimeInterval)
    /// Operation was cancelled.
    case cancelled
    /// Catch-all for unexpected errors.
    case unknown(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        // Config
        case .config(let e):            return e.localizedDescription
        case .configSync(let e):        return e.localizedDescription
        case .configMerge(let e):       return "配置合并失败: \(e.localizedDescription)"

        // Transport
        case .transport(let e):         return e.localizedDescription
        case .proxyGroup(let e):        return e.localizedDescription

        // Protocol
        case .protocolOutbound(let e):  return e.localizedDescription

        // Runtime
        case .runtime(let e):           return e.localizedDescription
        case .core(let e):              return e.localizedDescription
        case .api(let e):               return e.localizedDescription
        case .download(let e):          return e.localizedDescription

        // VPN
        case .vpn(let e):               return e.localizedDescription
        case .tunnelRouting(let e):     return e.localizedDescription
        case .tunnel(let e):            return e.localizedDescription

        // XPC
        case .xpc(let e):               return e.localizedDescription
        case .xpcConnection(let e):     return e.localizedDescription

        // App
        case .profile(let e):           return e.localizedDescription
        case .subscription(let e):      return e.localizedDescription
        case .systemProxy(let e):       return e.localizedDescription
        case .keychain(let e):          return e.localizedDescription

        // Generic
        case .underlying(_, let ctx):   return ctx
        case .timeout(let op, let dur): return "操作超时: \(op) (\(Int(dur))s)"
        case .cancelled:                return "操作已取消"
        case .unknown(let msg):         return msg
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .config:           return "请检查 YAML 配置文件格式是否正确"
        case .configSync:       return "请检查 WebDAV 服务器地址和凭据"
        case .transport:        return "请检查网络连接和代理节点是否可用"
        case .runtime:          return "请尝试重新启动 mihomo 内核"
        case .core:             return "请检查 mihomo 是否已正确安装"
        case .download:         return "请检查网络连接后重试"
        case .xpc, .xpcConnection:
            return "请尝试重新安装 Helper 工具"
        case .profile:          return "请检查配置文件是否完整"
        case .subscription:     return "请检查订阅 URL 是否有效"
        case .systemProxy:      return "请检查系统代理设置权限"
        case .timeout:          return "操作耗时过长，请稍后重试"
        case .cancelled:        return nil
        default:                return nil
        }
    }
}

// MARK: - Convenience Extensions

extension RiptideError {
    /// Whether this error represents a timeout.
    public var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }

    /// Whether this error represents cancellation.
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// A short category label for logging / UI grouping.
    public var category: String {
        switch self {
        case .config, .configSync, .configMerge:     return "配置"
        case .transport, .proxyGroup:                 return "传输"
        case .protocolOutbound:                       return "协议"
        case .runtime, .core, .api, .download:        return "运行时"
        case .vpn, .tunnelRouting, .tunnel:            return "VPN"
        case .xpc, .xpcConnection:                    return "XPC"
        case .profile, .subscription, .systemProxy, .keychain: return "应用"
        case .underlying:                             return "底层"
        case .timeout:                                return "超时"
        case .cancelled:                              return "取消"
        case .unknown:                                return "未知"
        }
    }
}
