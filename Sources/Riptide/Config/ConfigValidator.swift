import Foundation
import Yams

/// Actor-based configuration validator
public actor ConfigValidator {

    public init() {}

    /// Validate complete YAML configuration
    public func validate(yaml: String) -> ConfigValidationResult {
        var issues: [ValidationIssue] = []

        // 1. Syntax validation
        issues.append(contentsOf: validateSyntax(yaml: yaml))

        // 2. Structure validation
        issues.append(contentsOf: validateStructure(yaml: yaml))

        // 3. Semantic validation
        issues.append(contentsOf: validateSemantics(yaml: yaml))

        return ConfigValidationResult(issues: issues)
    }

    /// Validate YAML syntax only
    private func validateSyntax(yaml: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        do {
            _ = try Yams.load(yaml: yaml)
        } catch {
            // Extract line number from error if possible
            let errorStr = String(describing: error)
            var line: Int?
            var column: Int?

            // Yams errors often contain line info
            let linePattern = "line (\\d+)"
            if let regex = try? NSRegularExpression(pattern: linePattern, options: []),
               let match = regex.firstMatch(in: errorStr, options: [], range: NSRange(location: 0, length: errorStr.utf16.count)) {
                let lineStr = (errorStr as NSString).substring(with: match.range(at: 1))
                line = Int(lineStr)
            }

            // Try to extract column
            let colPattern = "column (\\d+)"
            if let regex = try? NSRegularExpression(pattern: colPattern, options: []),
               let match = regex.firstMatch(in: errorStr, options: [], range: NSRange(location: 0, length: errorStr.utf16.count)) {
                let colStr = (errorStr as NSString).substring(with: match.range(at: 1))
                column = Int(colStr)
            }

            issues.append(ValidationIssue(
                line: line,
                column: column,
                severity: .error,
                message: "YAML syntax error: \(errorStr)",
                path: "",
                suggestion: "Check YAML indentation and structure"
            ))
        }

        return issues
    }

    /// Validate configuration structure
    private func validateStructure(yaml: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        guard let raw = try? Yams.load(yaml: yaml) as? [String: Any] else {
            return issues  // Syntax error already reported
        }

        // Validate proxies structure
        if let proxies = raw["proxies"] as? [[String: Any]] {
            issues.append(contentsOf: validateProxiesStructure(proxies))
        }

        // Validate proxy-groups structure
        if let groups = raw["proxy-groups"] as? [[String: Any]] {
            issues.append(contentsOf: validateProxyGroupsStructure(groups))
        }

        // Validate rules
        if let rules = raw["rules"] as? [String] {
            issues.append(contentsOf: validateRulesStructure(rules))
        }

        // Validate mode
        if let mode = raw["mode"] as? String {
            let validModes = ["rule", "global", "direct"]
            if !validModes.contains(mode.lowercased()) {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Unknown mode: \(mode)",
                    path: "mode",
                    suggestion: "Valid modes: rule, global, direct"
                ))
            }
        }

        return issues
    }

    /// Validate proxies array
    private func validateProxiesStructure(_ proxies: [[String: Any]]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var names: Set<String> = []

        for (index, proxy) in proxies.enumerated() {
            let path = "proxies[\(index)]"

            // Check required fields
            guard let name = proxy["name"] as? String else {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Proxy at index \(index) missing required field: name",
                    path: path,
                    suggestion: "Add a unique name to the proxy"
                ))
                continue
            }

            // Validate name uniqueness
            if let issue = ProxyValidationRules.validateProxyName(name, existingNames: names) {
                let updatedIssue = ValidationIssue(
                    line: nil,
                    column: nil,
                    severity: issue.severity,
                    message: issue.message,
                    path: "\(path).\(issue.path)",
                    suggestion: issue.suggestion
                )
                issues.append(updatedIssue)
            }
            names.insert(name)

            // Validate server
            if let server = proxy["server"] as? String,
               let issue = ProxyValidationRules.validateServer(server) {
                issues.append(ValidationIssue(
                    line: nil,
                    column: nil,
                    severity: issue.severity,
                    message: issue.message,
                    path: "\(path).\(issue.path)",
                    suggestion: issue.suggestion
                ))
            }

            // Validate port
            if let port = proxy["port"] as? Int {
                if let issue = ProxyValidationRules.validatePort(port) {
                    issues.append(ValidationIssue(
                        line: nil,
                        column: nil,
                        severity: issue.severity,
                        message: issue.message,
                        path: "\(path).\(issue.path)",
                        suggestion: issue.suggestion
                    ))
                }
            } else if proxy["port"] == nil {
                // Port is missing
                let type = proxy["type"] as? String ?? ""
                if type.lowercased() != "relay" {
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Missing required field: port",
                        path: "\(path).port",
                        suggestion: "Add port number (1-65535) for the proxy"
                    ))
                }
            }

            // Get proxy type
            let type = proxy["type"] as? String ?? ""
            let proxyKind = parseProxyKind(type)

            // Check required fields based on type
            if let required = ProxyValidationRules.requiredFields[proxyKind] {
                for field in required {
                    if proxy[field] == nil {
                        issues.append(ValidationIssue(
                            severity: .error,
                            message: "Missing required field '\(field)' for \(type) proxy",
                            path: "\(path).\(field)",
                            suggestion: "Add '\(field)' to the proxy configuration"
                        ))
                    }
                }
            }

            // Validate UUID for VMess/VLESS/TUIC
            if [.vmess, .vless, .tuic].contains(proxyKind) {
                if let uuid = proxy["uuid"] as? String,
                   let issue = ProxyValidationRules.validateUUID(uuid) {
                    issues.append(ValidationIssue(
                        line: nil,
                        column: nil,
                        severity: issue.severity,
                        message: issue.message,
                        path: "\(path).\(issue.path)",
                        suggestion: issue.suggestion
                    ))
                }
            }

            // Validate cipher for Shadowsocks
            if proxyKind == .shadowsocks || type.lowercased() == "ss" {
                if let cipher = proxy["cipher"] as? String,
                   !ProxyValidationRules.validSSCiphers.contains(cipher) {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Unknown Shadowsocks cipher: \(cipher)",
                        path: "\(path).cipher",
                        suggestion: "Valid ciphers: \(ProxyValidationRules.validSSCiphers.joined(separator: ", "))"
                    ))
                }
            }

            // Validate cipher for VMess
            if proxyKind == .vmess {
                if let cipher = proxy["cipher"] as? String,
                   !ProxyValidationRules.validVMessCiphers.contains(cipher) {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Unknown VMess cipher: \(cipher)",
                        path: "\(path).cipher",
                        suggestion: "Valid ciphers: \(ProxyValidationRules.validVMessCiphers.joined(separator: ", "))"
                    ))
                }
            }

            // Validate TUIC-specific fields
            if proxyKind == .tuic {
                if let congestion = proxy["congestion-control"] as? String,
                   let issue = ProxyValidationRules.validateTUICCongestionControl(congestion) {
                    issues.append(ValidationIssue(
                        line: nil,
                        column: nil,
                        severity: issue.severity,
                        message: issue.message,
                        path: "\(path).\(issue.path)",
                        suggestion: issue.suggestion
                    ))
                }

                if let udpRelay = proxy["udp-relay-mode"] as? String,
                   let issue = ProxyValidationRules.validateTUICUDPRelayMode(udpRelay) {
                    issues.append(ValidationIssue(
                        line: nil,
                        column: nil,
                        severity: issue.severity,
                        message: issue.message,
                        path: "\(path).\(issue.path)",
                        suggestion: issue.suggestion
                    ))
                }
            }
        }

        return issues
    }

    /// Validate proxy groups structure
    private func validateProxyGroupsStructure(_ groups: [[String: Any]]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var names: Set<String> = []

        for (index, group) in groups.enumerated() {
            let path = "proxy-groups[\(index)]"

            // Validate name
            if let name = group["name"] as? String {
                if let issue = ProxyGroupValidationRules.validateGroupName(name, existingNames: names) {
                    issues.append(ValidationIssue(
                        line: nil,
                        column: nil,
                        severity: issue.severity,
                        message: issue.message,
                        path: "\(path).\(issue.path)",
                        suggestion: issue.suggestion
                    ))
                }
                names.insert(name)
            } else {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Proxy group at index \(index) missing required field: name",
                    path: path,
                    suggestion: "Add a unique name to the group"
                ))
            }

            // Validate type
            if let type = group["type"] as? String,
               let issue = ProxyGroupValidationRules.validateGroupType(type) {
                issues.append(ValidationIssue(
                    line: nil,
                    column: nil,
                    severity: issue.severity,
                    message: issue.message,
                    path: "\(path).\(issue.path)",
                    suggestion: issue.suggestion
                ))
            } else if group["type"] == nil {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Missing required field: type",
                    path: "\(path).type",
                    suggestion: "Add type to the group (select, url-test, fallback, load-balance)"
                ))
            }

            // Warn if proxies list is empty
            if let proxies = group["proxies"] as? [String], proxies.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Proxy group has empty proxies list",
                    path: "\(path).proxies",
                    suggestion: "Add at least one proxy to the group"
                ))
            }
        }

        return issues
    }

    /// Validate rules structure
    private func validateRulesStructure(_ rules: [String]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        for (index, rule) in rules.enumerated() {
            let path = "rules[\(index)]"

            // Check format
            if let issue = RuleValidationRules.validateRuleFormat(rule, at: index) {
                issues.append(issue)
                continue
            }

            let parts = rule.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let ruleType = parts[0].uppercased()

            // Validate rule type
            if let issue = RuleValidationRules.validateRuleType(parts[0], at: index) {
                issues.append(issue)
            }

            // Validate CIDR for IP rules
            if ruleType == "IP-CIDR" || ruleType == "IP-CIDR6" || ruleType == "SRC-IP-CIDR" {
                if parts.count >= 2 {
                    if let issue = RuleValidationRules.validateIPCIDR(parts[1], at: index) {
                        issues.append(ValidationIssue(
                            line: nil,
                            column: nil,
                            severity: issue.severity,
                            message: issue.message,
                            path: issue.path,
                            suggestion: issue.suggestion
                        ))
                    }
                }
            }

            // Validate port numbers for port rules
            if ruleType == "SRC-PORT" || ruleType == "DST-PORT" {
                if parts.count >= 2 {
                    let portStr = parts[1]
                    if let port = Int(portStr) {
                        if let issue = ProxyValidationRules.validatePort(port) {
                            issues.append(ValidationIssue(
                                line: nil,
                                column: nil,
                                severity: issue.severity,
                                message: issue.message,
                                path: "\(path).port",
                                suggestion: issue.suggestion
                            ))
                        }
                    } else {
                        issues.append(ValidationIssue(
                            severity: .error,
                            message: "Invalid port number: \(portStr)",
                            path: "\(path).port",
                            suggestion: "Port must be a valid integer between 1-65535"
                        ))
                    }
                }
            }
        }

        return issues
    }

    /// Validate semantics (reference validation)
    private func validateSemantics(yaml: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        guard let raw = try? Yams.load(yaml: yaml) as? [String: Any] else {
            return issues
        }

        // Collect all proxy names
        let proxyNames = Set((raw["proxies"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        let groupNames = Set((raw["proxy-groups"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        let allNames = proxyNames.union(groupNames)

        // Check proxy-group references
        if let groups = raw["proxy-groups"] as? [[String: Any]] {
            for (index, group) in groups.enumerated() {
                if let proxies = group["proxies"] as? [String] {
                    for (proxyIndex, proxyName) in proxies.enumerated() {
                        if !allNames.contains(proxyName) {
                            // Check if it might be a built-in policy
                            let builtInPolicies = ["DIRECT", "REJECT", "PROXY", "GLOBAL"]
                            if !builtInPolicies.contains(proxyName.uppercased()) {
                                issues.append(ValidationIssue(
                                    severity: .error,
                                    message: "Proxy '\(proxyName)' referenced in group but not defined",
                                    path: "proxy-groups[\(index)].proxies[\(proxyIndex)]",
                                    suggestion: "Add '\(proxyName)' to proxies section or correct the name"
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Check rule policy references
        if let rules = raw["rules"] as? [String] {
            for (index, rule) in rules.enumerated() {
                let parts = rule.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2 else { continue }

                let ruleType = parts[0].uppercased()
                let policyName: String

                if ruleType == "MATCH" || ruleType == "FINAL" {
                    policyName = parts[1]
                } else if ruleType == "REJECT" {
                    continue
                } else if parts.count >= 3 {
                    policyName = parts[parts.count - 1]
                } else {
                    continue
                }

                // Check if policy is valid
                let builtInPolicies = ["DIRECT", "REJECT", "PROXY"]
                if !builtInPolicies.contains(policyName.uppercased()) && !allNames.contains(policyName) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Policy '\(policyName)' referenced in rule but not defined",
                        path: "rules[\(index)]",
                        suggestion: "Add '\(policyName)' to proxies/proxy-groups or use DIRECT/REJECT"
                    ))
                }
            }
        }

        return issues
    }

    /// Parse proxy kind from type string
    private func parseProxyKind(_ type: String) -> ProxyKind {
        switch type.lowercased() {
        case "ss", "shadowsocks": return .shadowsocks
        case "vmess": return .vmess
        case "vless": return .vless
        case "trojan": return .trojan
        case "hysteria2", "hy2": return .hysteria2
        case "tuic": return .tuic
        case "http", "https": return .http
        case "socks5": return .socks5
        case "relay": return .relay
        case "snell": return .snell
        default: return .http
        }
    }
}
