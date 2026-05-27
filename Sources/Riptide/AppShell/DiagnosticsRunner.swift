import Foundation

// MARK: - Diagnostic Check Result

/// Result of a single diagnostic check.
public struct DiagnosticCheck: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let status: Status
    public let detail: String
    public let suggestion: String?

    public enum Status: Sendable, Equatable {
        case passed
        case warning
        case failed

        public var icon: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }

    public init(id: String, name: String, status: Status, detail: String, suggestion: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.detail = detail
        self.suggestion = suggestion
    }
}

// MARK: - Active Diagnostics Report

/// Complete result of an active diagnostic sweep (connectivity/DNS/port checks).
/// Distinct from `DiagnosticReport` which is a passive runtime-state snapshot.
public struct ActiveDiagnosticsReport: Sendable {
    public let timestamp: Date
    public let checks: [DiagnosticCheck]
    public let passedCount: Int
    public let warningCount: Int
    public let failedCount: Int

    public var allPassed: Bool { failedCount == 0 && warningCount == 0 }
    public var hasFailures: Bool { failedCount > 0 }
}

// MARK: - Diagnostics Runner

/// Runs a battery of diagnostic checks for the Riptide proxy setup.
public actor DiagnosticsRunner {

    public init() {}

    // MARK: - Run All Checks

    /// Runs all diagnostic checks and returns a report.
    public func runDiagnostics() async -> ActiveDiagnosticsReport {
        let checks: [DiagnosticCheck] = await [
            checkHelperInstallation(),
            checkCoreBinary(),
            checkNetworkConnectivity(),
            checkDNSResolution(),
            checkProxyListening(),
            checkConfigIntegrity(),
        ]

        let passed = checks.filter { $0.status == .passed }.count
        let warnings = checks.filter { $0.status == .warning }.count
        let failures = checks.filter { $0.status == .failed }.count

        return ActiveDiagnosticsReport(
            timestamp: Date(),
            checks: checks,
            passedCount: passed,
            warningCount: warnings,
            failedCount: failures
        )
    }

    // MARK: - Individual Checks

    /// Check 1: Helper tool / privileged service is installed.
    private func checkHelperInstallation() async -> DiagnosticCheck {
        let helperPlist = "/Library/LaunchDaemons/com.riptide.helper.plist"
        let helperBinary = "/Library/PrivilegedHelperTools/com.riptide.helper"

        let plistExists = FileManager.default.fileExists(atPath: helperPlist)
        let binaryExists = FileManager.default.fileExists(atPath: helperBinary)

        if plistExists && binaryExists {
            return DiagnosticCheck(
                id: "helper",
                name: "Helper 服务",
                status: .passed,
                detail: "Helper 已安装: plist + binary 均存在"
            )
        } else if binaryExists {
            return DiagnosticCheck(
                id: "helper",
                name: "Helper 服务",
                status: .warning,
                detail: "Binary 存在但 LaunchDaemon plist 缺失",
                suggestion: "在设置中重新安装 Helper，或手动执行 sudo 注册"
            )
        } else {
            return DiagnosticCheck(
                id: "helper",
                name: "Helper 服务",
                status: .failed,
                detail: "Helper 未安装",
                suggestion: "在设置 → Helper 中安装，或使用 sudo 模式启动"
            )
        }
    }

    /// Check 2: mihomo / sing-box binary is available at the expected path.
    private func checkCoreBinary() async -> DiagnosticCheck {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        let mihomoPath = appSupport
            .appendingPathComponent("Riptide/mihomo/mihomo")
            .path
        let singBoxPath = appSupport
            .appendingPathComponent("Riptide/Binaries/sing-box")
            .path

        let mihomoExists = FileManager.default.isExecutableFile(atPath: mihomoPath)
        let singBoxExists = FileManager.default.isExecutableFile(atPath: singBoxPath)

        if mihomoExists || singBoxExists {
            let available = [mihomoExists ? "mihomo" : nil, singBoxExists ? "sing-box" : nil]
                .compactMap { $0 }.joined(separator: ", ")
            return DiagnosticCheck(
                id: "core_binary",
                name: "代理内核",
                status: .passed,
                detail: "可用内核: \(available)"
            )
        } else {
            return DiagnosticCheck(
                id: "core_binary",
                name: "代理内核",
                status: .failed,
                detail: "未找到 mihomo 或 sing-box 可执行文件",
                suggestion: "在设置 → 内核中下载至少一个内核"
            )
        }
    }

    /// Check 3: Basic network connectivity to a well-known endpoint.
    private func checkNetworkConnectivity() async -> DiagnosticCheck {
        let testURL = URL(string: "https://www.apple.com")!
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200...399).contains(httpResponse.statusCode) {
                return DiagnosticCheck(
                    id: "connectivity",
                    name: "网络连接",
                    status: .passed,
                    detail: "可访问 apple.com (HTTP \(httpResponse.statusCode))"
                )
            }
            return DiagnosticCheck(
                id: "connectivity",
                name: "网络连接",
                status: .warning,
                detail: "apple.com 返回非预期状态码",
                suggestion: "检查网络连接是否正常"
            )
        } catch {
            return DiagnosticCheck(
                id: "connectivity",
                name: "网络连接",
                status: .failed,
                detail: "无法连接互联网: \(error.localizedDescription)",
                suggestion: "检查 WiFi/以太网连接，确认未启用防火墙阻断"
            )
        }
    }

    /// Check 4: DNS resolution works.
    private func checkDNSResolution() async -> DiagnosticCheck {
        let testDomains = ["www.apple.com", "www.google.com", "github.com"]
        var resolved = 0
        var failed = 0

        for domain in testDomains {
            let host = CFHostCreateWithName(nil, domain as CFString).takeRetainedValue()
            var resolvedRef: DarwinBoolean = false
            CFHostStartInfoResolution(host, .addresses, nil)
            if let addresses = CFHostGetAddressing(host, &resolvedRef) as? [Data],
               !addresses.isEmpty {
                resolved += 1
            } else {
                failed += 1
            }
        }

        if failed == 0 {
            return DiagnosticCheck(
                id: "dns",
                name: "DNS 解析",
                status: .passed,
                detail: "\(resolved)/\(testDomains.count) 个域名解析成功"
            )
        } else if resolved > 0 {
            return DiagnosticCheck(
                id: "dns",
                name: "DNS 解析",
                status: .warning,
                detail: "\(resolved)/\(testDomains.count) 成功，\(failed) 个失败",
                suggestion: "部分 DNS 解析失败，尝试切换 DNS 服务器"
            )
        } else {
            return DiagnosticCheck(
                id: "dns",
                name: "DNS 解析",
                status: .failed,
                detail: "所有域名解析失败",
                suggestion: "DNS 服务不可用，检查网络设置或重启路由器"
            )
        }
    }

    /// Check 5: Check if the proxy is listening on expected ports.
    private func checkProxyListening() async -> DiagnosticCheck {
        let testPorts = [6152, 7890, 9090]
        var listening: [Int] = []

        for port in testPorts {
            let host = CFHostCreateWithName(nil, "127.0.0.1" as CFString).takeRetainedValue()
            // Simple check: try connecting via URLSession with a very short timeout
            if let url = URL(string: "http://127.0.0.1:\(port)") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 2
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        listening.append(port)
                    }
                } catch {
                    // Port not listening — expected if proxy not running
                }
            }
        }

        if !listening.isEmpty {
            return DiagnosticCheck(
                id: "proxy_port",
                name: "代理端口",
                status: .passed,
                detail: "端口 \(listening.map(String.init).joined(separator: ", ")) 已监听"
            )
        } else {
            return DiagnosticCheck(
                id: "proxy_port",
                name: "代理端口",
                status: .warning,
                detail: "未检测到代理端口监听 (检查了 6152, 7890, 9090)",
                suggestion: "启动代理服务，确认 mihomo/sing-box 进程正常运行"
            )
        }
    }

    /// Check 6: Current configuration integrity.
    private func checkConfigIntegrity() async -> DiagnosticCheck {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        let configPath = appSupport
            .appendingPathComponent("Riptide/mihomo/config.yaml")
            .path

        guard FileManager.default.fileExists(atPath: configPath) else {
            return DiagnosticCheck(
                id: "config",
                name: "配置文件",
                status: .warning,
                detail: "config.yaml 不存在",
                suggestion: "导入 Clash 配置或订阅以生成配置文件"
            )
        }

        do {
            let yaml = try String(contentsOfFile: configPath, encoding: .utf8)
            let hasProxies = yaml.contains("proxies:")
            let hasRules = yaml.contains("rules:")
            let hasPort = yaml.contains("port:") || yaml.contains("mixed-port:")

            if hasProxies && hasRules && hasPort {
                return DiagnosticCheck(
                    id: "config",
                    name: "配置文件",
                    status: .passed,
                    detail: "config.yaml 包含 proxies + rules + port"
                )
            } else {
                var missing: [String] = []
                if !hasProxies { missing.append("proxies") }
                if !hasRules { missing.append("rules") }
                if !hasPort { missing.append("port") }
                return DiagnosticCheck(
                    id: "config",
                    name: "配置文件",
                    status: .warning,
                    detail: "config.yaml 缺少: \(missing.joined(separator: ", "))",
                    suggestion: "检查配置文件是否完整"
                )
            }
        } catch {
            return DiagnosticCheck(
                id: "config",
                name: "配置文件",
                status: .failed,
                detail: "无法读取 config.yaml: \(error.localizedDescription)",
                suggestion: "检查文件权限或重新生成配置"
            )
        }
    }
}
