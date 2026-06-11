import Foundation
import Riptide

extension RuleTarget {
    /// Parses a user-entered domain or IP (with optional :port) into a `RuleTarget`.
    /// - "www.google.com" -> domain = "www.google.com"
    /// - "1.1.1.1" -> ipAddress = "1.1.1.1"
    /// - "example.com:443" -> domain = "example.com", destinationPort = 443
    /// - "::1" -> ipAddress = "::1" (IPv6)
    static func parse(_ input: String) -> RuleTarget {
        var domain: String?
        var ip: String?
        var port: Int?

        var working = input
        // Only treat a trailing ":port" as a port if there is exactly one
        // ":" in the input. IPv6 addresses use ":" as a separator and
        // commonly appear as "::1" or "fe80::1", so any input with more
        // than one ":" is treated as a literal IPv6 address (no port).
        let colonCount = input.filter { $0 == ":" }.count
        if colonCount == 1,
           let colonRange = input.range(of: ":", options: .backwards),
           let portNum = Int(input[colonRange.upperBound...]) {
            port = portNum
            working = String(input[..<colonRange.lowerBound])
        }

        if working.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) {
            ip = working
        } else {
            domain = working
        }

        return RuleTarget(
            domain: domain,
            ipAddress: ip,
            sourceIP: nil,
            sourcePort: nil,
            destinationPort: port
        )
    }
}
