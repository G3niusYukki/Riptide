import Foundation

/// Configuration for MITM interception — defines which hosts to intercept.
public struct MITMConfig: Sendable, Equatable {
    /// Whether MITM interception is globally enabled.
    public var enabled: Bool

    /// Host patterns to intercept. Supports wildcards like `*.example.com`.
    public var hosts: [String]

    /// Hosts to explicitly exclude from interception.
    public var excludeHosts: [String]

    public init(enabled: Bool = false, hosts: [String] = [], excludeHosts: [String] = []) {
        self.enabled = enabled
        self.hosts = hosts
        self.excludeHosts = excludeHosts
    }

    /// Returns whether a given host should be intercepted.
    public func shouldIntercept(_ host: String) -> Bool {
        guard enabled else { return false }
        // Check exclusions first
        for pattern in excludeHosts {
            if match(host: host, pattern: pattern) {
                return false
            }
        }
        // If no specific hosts configured, intercept all
        if hosts.isEmpty {
            return true
        }
        // Match against configured patterns
        for pattern in hosts {
            if match(host: host, pattern: pattern) {
                return true
            }
        }
        return false
    }

    /// Matches a host against a pattern. Supports `*` wildcard.
    private func match(host: String, pattern: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == host { return true }

        // Wildcard matching: *.example.com matches any.example.com
        if pattern.hasPrefix("*.") {
            let suffix = pattern.dropFirst(2)
            return host.hasSuffix(suffix) || host == String(suffix)
        }

        return false
    }
}
