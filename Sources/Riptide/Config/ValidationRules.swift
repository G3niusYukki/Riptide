import Foundation

/// Rules for validating proxy configurations
public enum ProxyValidationRules: Sendable {

    /// Required fields for each proxy type
    public static let requiredFields: [ProxyKind: [String]] = [
        .shadowsocks: ["name", "type", "server", "port", "cipher", "password"],
        .vmess: ["name", "type", "server", "port", "uuid", "cipher"],
        .vless: ["name", "type", "server", "port", "uuid"],
        .trojan: ["name", "type", "server", "port", "password"],
        .hysteria2: ["name", "type", "server", "port", "password"],
        .tuic: ["name", "type", "server", "port", "uuid", "password"],
        .http: ["name", "type", "server", "port"],
        .socks5: ["name", "type", "server", "port"],
        .relay: ["name", "type", "server", "port", "chain"],
        .snell: ["name", "type", "server", "port", "password"]
    ]

    /// Valid cipher methods for Shadowsocks
    public static let validSSCiphers: Set<String> = [
        "aes-128-gcm", "aes-192-gcm", "aes-256-gcm",
        "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
        "aes-128-ctr", "aes-192-ctr", "aes-256-ctr",
        "aes-128-cfb", "aes-192-cfb", "aes-256-cfb",
        "rc4-md5", "chacha20", "chacha20-ietf"
    ]

    /// Valid cipher methods for VMess
    public static let validVMessCiphers: Set<String> = [
        "auto", "aes-128-gcm", "chacha20-poly1305", "none"
    ]

    /// Valid congestion control for TUIC
    public static let validTUICCongestionControl: Set<String> = [
        "bbr", "cubic", "new_reno"
    ]

    /// Valid UDP relay modes for TUIC
    public static let validTUICUDPRelayModes: Set<String> = [
        "native", "quic"
    ]

    /// Validate port number
    public static func validatePort(_ port: Int) -> ValidationIssue? {
        if port < 1 || port > 65535 {
            return ValidationIssue(
                severity: .error,
                message: "Port \(port) is out of valid range (1-65535)",
                path: "port",
                suggestion: "Use a port between 1 and 65535"
            )
        }
        return nil
    }

    /// Validate UUID format
    public static func validateUUID(_ uuid: String) -> ValidationIssue? {
        let uuidRegex = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidRegex)
        if !predicate.evaluate(with: uuid) {
            return ValidationIssue(
                severity: .error,
                message: "Invalid UUID format: \(uuid)",
                path: "uuid",
                suggestion: "UUID should be in format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            )
        }
        return nil
    }

    /// Validate proxy name (should be unique and valid)
    public static func validateProxyName(_ name: String, existingNames: Set<String>) -> ValidationIssue? {
        if name.isEmpty {
            return ValidationIssue(
                severity: .error,
                message: "Proxy name cannot be empty",
                path: "name",
                suggestion: "Provide a unique name for the proxy"
            )
        }

        let invalidChars = CharacterSet(charactersIn: "@#$/\\%")
        if name.rangeOfCharacter(from: invalidChars) != nil {
            return ValidationIssue(
                severity: .warning,
                message: "Proxy name contains special characters",
                path: "name",
                suggestion: "Use alphanumeric characters, hyphens, and underscores only"
            )
        }

        if existingNames.contains(name) {
            return ValidationIssue(
                severity: .error,
                message: "Duplicate proxy name: \(name)",
                path: "name",
                suggestion: "Use a unique name for each proxy"
            )
        }

        return nil
    }

    /// Validate server hostname or IP
    public static func validateServer(_ server: String) -> ValidationIssue? {
        if server.isEmpty {
            return ValidationIssue(
                severity: .error,
                message: "Server address cannot be empty",
                path: "server",
                suggestion: "Provide a valid hostname or IP address"
            )
        }

        // Check for invalid characters in server address
        let invalidChars = CharacterSet(charactersIn: " ")
        if server.rangeOfCharacter(from: invalidChars) != nil {
            return ValidationIssue(
                severity: .error,
                message: "Server address contains spaces",
                path: "server",
                suggestion: "Remove spaces from the server address"
            )
        }

        return nil
    }

    /// Validate TUIC congestion control
    public static func validateTUICCongestionControl(_ value: String) -> ValidationIssue? {
        if !validTUICCongestionControl.contains(value) {
            return ValidationIssue(
                severity: .warning,
                message: "Unknown TUIC congestion control: \(value)",
                path: "congestion-control",
                suggestion: "Valid options: \(validTUICCongestionControl.joined(separator: ", "))"
            )
        }
        return nil
    }

    /// Validate TUIC UDP relay mode
    public static func validateTUICUDPRelayMode(_ value: String) -> ValidationIssue? {
        if !validTUICUDPRelayModes.contains(value) {
            return ValidationIssue(
                severity: .warning,
                message: "Unknown TUIC UDP relay mode: \(value)",
                path: "udp-relay-mode",
                suggestion: "Valid options: \(validTUICUDPRelayModes.joined(separator: ", "))"
            )
        }
        return nil
    }
}

/// Rules for validating proxy groups
public enum ProxyGroupValidationRules: Sendable {
    public static let validTypes: Set<String> = ["select", "url-test", "fallback", "load-balance", "relay"]

    public static func validateGroupType(_ type: String) -> ValidationIssue? {
        if !validTypes.contains(type.lowercased()) {
            return ValidationIssue(
                severity: .error,
                message: "Invalid proxy group type: \(type)",
                path: "type",
                suggestion: "Valid types: \(validTypes.joined(separator: ", "))"
            )
        }
        return nil
    }

    public static func validateGroupName(_ name: String, existingNames: Set<String>) -> ValidationIssue? {
        if name.isEmpty {
            return ValidationIssue(
                severity: .error,
                message: "Proxy group name cannot be empty",
                path: "name",
                suggestion: "Provide a unique name for the group"
            )
        }

        if existingNames.contains(name) {
            return ValidationIssue(
                severity: .error,
                message: "Duplicate group name: \(name)",
                path: "name",
                suggestion: "Use a unique name for each group"
            )
        }

        return nil
    }
}

/// Rules for validating rules
public enum RuleValidationRules: Sendable {
    public static let validTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD",
        "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR",
        "SRC-PORT", "DST-PORT", "PROCESS-NAME",
        "GEOIP", "GEOSITE", "IP-ASN", "RULE-SET",
        "SCRIPT", "NOT", "MATCH", "FINAL", "REJECT"
    ]

    public static let validPolicies: Set<String> = ["DIRECT", "REJECT", "PROXY"]

    /// Validate rule format
    public static func validateRuleFormat(_ rule: String, at index: Int) -> ValidationIssue? {
        let parts = rule.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 2 else {
            return ValidationIssue(
                severity: .error,
                message: "Invalid rule format at index \(index): too few components",
                path: "rules[\(index)]",
                suggestion: "Rule format: TYPE,VALUE,POLICY or MATCH,POLICY"
            )
        }

        let ruleType = parts[0].uppercased()

        // Special handling for MATCH/FINAL
        if ruleType == "MATCH" || ruleType == "FINAL" {
            guard parts.count == 2 else {
                return ValidationIssue(
                    severity: .error,
                    message: "MATCH/FINAL rule requires exactly 2 components: TYPE,POLICY",
                    path: "rules[\(index)]",
                    suggestion: "Format: MATCH,DIRECT or MATCH,PROXY"
                )
            }
            return nil
        }

        // Special handling for REJECT
        if ruleType == "REJECT" {
            return nil
        }

        // Special handling for NOT rules
        if ruleType == "NOT" {
            guard parts.count >= 4 else {
                return ValidationIssue(
                    severity: .error,
                    message: "NOT rule requires at least 4 components",
                    path: "rules[\(index)]",
                    suggestion: "Format: NOT,RULE_TYPE,VALUE,POLICY"
                )
            }
            return nil
        }

        // Standard rules need 3 parts
        guard parts.count >= 3 else {
            return ValidationIssue(
                severity: .error,
                message: "Rule '\(ruleType)' requires 3 components",
                path: "rules[\(index)]",
                suggestion: "Format: \(ruleType),VALUE,POLICY"
            )
        }

        return nil
    }

    /// Validate rule type
    public static func validateRuleType(_ type: String, at index: Int) -> ValidationIssue? {
        let upperType = type.uppercased()
        if !validTypes.contains(upperType) {
            return ValidationIssue(
                severity: .warning,
                message: "Unknown rule type: \(type)",
                path: "rules[\(index)]",
                suggestion: "Valid types: \(validTypes.joined(separator: ", "))"
            )
        }
        return nil
    }

    /// Validate IP CIDR format
    public static func validateIPCIDR(_ cidr: String, at index: Int) -> ValidationIssue? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2 else {
            return ValidationIssue(
                severity: .error,
                message: "Invalid CIDR format: \(cidr)",
                path: "rules[\(index)]",
                suggestion: "Format should be: x.x.x.x/xx (e.g., 192.168.1.0/24)"
            )
        }

        guard let prefix = Int(parts[1]), prefix >= 0 && prefix <= 128 else {
            return ValidationIssue(
                severity: .error,
                message: "Invalid CIDR prefix length: \(parts[1])",
                path: "rules[\(index)]",
                suggestion: "Prefix must be between 0 and 128 (0-32 for IPv4, 0-128 for IPv6)"
            )
        }

        return nil
    }
}
