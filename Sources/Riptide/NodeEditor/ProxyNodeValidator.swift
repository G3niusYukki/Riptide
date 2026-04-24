import Foundation

// MARK: - Validation Types

/// Result of a validation operation
public struct ValidationResult: Equatable, Sendable {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String? = nil) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }

    /// A successful validation result
    public static let valid = ValidationResult(isValid: true, errorMessage: nil)
}

/// Errors thrown during node validation
public enum NodeValidationError: Error, Equatable, Sendable {
    case validationFailed([String])
    case invalidProxyKind
    case storeError(String)
}

// MARK: - Proxy Node Validator

/// Actor-based validator for proxy node configuration
public actor ProxyNodeValidator {

    /// Valid Shadowsocks ciphers
    private let validShadowsocksCiphers = [
        "aes-128-gcm",
        "aes-192-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "xchacha20-ietf-poly1305",
        "aes-128-ctr",
        "aes-192-ctr",
        "aes-256-ctr",
        "aes-128-cfb",
        "aes-192-cfb",
        "aes-256-cfb",
        "rc4-md5",
        "none"
    ]

    public init() {}

    /// Validates a complete proxy node configuration
    public func validate(node: ProxyNode) async -> NodeValidationDetails {
        var errors: [String] = []

        // Validate name
        let nameResult = await validate(name: node.name)
        if !nameResult.isValid {
            errors.append(nameResult.errorMessage ?? "Invalid name")
        }

        // Validate server
        let serverResult = await validate(server: node.server)
        if !serverResult.isValid {
            errors.append(serverResult.errorMessage ?? "Invalid server")
        }

        // Validate port
        let portResult = await validate(port: node.port)
        if !portResult.isValid {
            errors.append(portResult.errorMessage ?? "Invalid port")
        }

        // Validate kind-specific fields
        switch node.kind {
        case .shadowsocks:
            if node.cipher == nil || node.cipher?.isEmpty == true {
                errors.append("Shadowsocks requires a cipher")
            }
            if node.password == nil || node.password?.isEmpty == true {
                errors.append("Shadowsocks requires a password")
            }

        case .vmess:
            if node.uuid == nil || node.uuid?.isEmpty == true {
                errors.append("VMess requires a UUID")
            } else if let uuid = node.uuid, !(await validate(uuid: uuid).isValid) {
                errors.append("VMess requires a valid UUID")
            }

        case .vless:
            if node.uuid == nil || node.uuid?.isEmpty == true {
                errors.append("VLESS requires a UUID")
            } else if let uuid = node.uuid, !(await validate(uuid: uuid).isValid) {
                errors.append("VLESS requires a valid UUID")
            }

        case .trojan:
            if node.password == nil || node.password?.isEmpty == true {
                errors.append("Trojan requires a password")
            }

        case .hysteria2:
            if node.password == nil || node.password?.isEmpty == true {
                errors.append("Hysteria2 requires a password")
            }

        case .snell:
            if node.password == nil || node.password?.isEmpty == true {
                errors.append("Snell requires a password")
            }

        case .tuic:
            if node.password == nil || node.password?.isEmpty == true {
                errors.append("TUIC requires a password")
            }

        case .http, .socks5, .relay:
            // No additional required fields
            break
        }

        return NodeValidationDetails(isValid: errors.isEmpty, errors: errors)
    }

    /// Validates a proxy node name
    public func validate(name: String) async -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ValidationResult(isValid: false, errorMessage: "name cannot be empty")
        }
        return .valid
    }

    /// Validates a server address (IP or hostname)
    public func validate(server: String) async -> ValidationResult {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ValidationResult(isValid: false, errorMessage: "Server address cannot be empty")
        }

        // Check for valid IPv4, IPv6, or hostname
        if isValidIPAddress(trimmed) || isValidHostname(trimmed) {
            return .valid
        }

        return ValidationResult(isValid: false, errorMessage: "Invalid server address format")
    }

    /// Validates a port number
    public func validate(port: Int) async -> ValidationResult {
        if port < 1 || port > 65535 {
            return ValidationResult(isValid: false, errorMessage: "Port must be between 1 and 65535")
        }
        return .valid
    }

    /// Validates a cipher string for a specific proxy kind
    public func validateCipher(_ cipher: String?, for kind: ProxyKind) async -> ValidationResult {
        guard let cipher = cipher, !cipher.isEmpty else {
            return ValidationResult(isValid: false, errorMessage: "Cipher cannot be empty")
        }

        if kind == .shadowsocks && !validShadowsocksCiphers.contains(cipher) {
            return ValidationResult(isValid: false, errorMessage: "Invalid Shadowsocks cipher: \(cipher)")
        }

        return .valid
    }

    /// Validates a UUID string
    public func validate(uuid: String) async -> ValidationResult {
        let trimmed = uuid.trimmingCharacters(in: .whitespacesAndNewlines)

        // UUID format: 8-4-4-4-12 hex characters
        let uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let regex = try? NSRegularExpression(pattern: uuidPattern, options: [])
        let range = NSRange(location: 0, length: trimmed.utf16.count)

        if regex?.firstMatch(in: trimmed, options: [], range: range) != nil {
            return .valid
        }

        return ValidationResult(isValid: false, errorMessage: "Invalid UUID format")
    }

    // MARK: - Private Helpers

    private func isValidIPAddress(_ address: String) -> Bool {
        // IPv4 pattern
        let ipv4Pattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        let ipv4Regex = try? NSRegularExpression(pattern: ipv4Pattern, options: [])
        let ipv4Range = NSRange(location: 0, length: address.utf16.count)

        if ipv4Regex?.firstMatch(in: address, options: [], range: ipv4Range) != nil {
            return true
        }

        // IPv6 validation using a comprehensive regex
        // Supports full form, compressed form (::), and IPv4-mapped
        let ipv6Pattern = "^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){1,6}|:(?::[0-9a-fA-F]{1,4}){1,7}|::1|::)$"

        let ipv6Regex = try? NSRegularExpression(pattern: ipv6Pattern, options: [])
        let ipv6Range = NSRange(location: 0, length: address.utf16.count)

        if ipv6Regex?.firstMatch(in: address, options: [], range: ipv6Range) != nil {
            return true
        }

        return false
    }

    private func isValidHostname(_ hostname: String) -> Bool {
        // Hostname pattern: alphanumeric, hyphens, dots (but not starting/ending with hyphen or dot)
        let hostnamePattern = "^(?!-)[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$"
        let regex = try? NSRegularExpression(pattern: hostnamePattern, options: [])
        let range = NSRange(location: 0, length: hostname.utf16.count)

        return regex?.firstMatch(in: hostname, options: [], range: range) != nil
    }
}

/// Detailed validation results for a node
public struct NodeValidationDetails: Equatable, Sendable {
    public let isValid: Bool
    public let errors: [String]

    public init(isValid: Bool, errors: [String]) {
        self.isValid = isValid
        self.errors = errors
    }
}
