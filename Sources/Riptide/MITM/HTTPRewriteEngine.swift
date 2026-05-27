import Foundation

// MARK: - HTTP Rewrite Engine

/// Applies URL-rewrite and header-modification rules to HTTP requests.
/// Operates on plaintext HTTP traffic (no TLS interception required).
public struct HTTPRewriteEngine: Sendable {

    private var rules: [RewriteRule] = []

    public init(rules: [RewriteRule] = []) {
        self.rules = rules
    }

    /// Replace all active rules.
    public mutating func setRules(_ rules: [RewriteRule]) {
        self.rules = rules
    }

    // MARK: - Request Matching

    /// Check if a URL matches any enabled reject rule.
    /// Returns `.reject` if matched, or nil.
    public func matchReject(url: String) -> RewriteRule.RewriteAction? {
        for rule in rules where rule.enabled {
            if case .reject = rule.action,
               matches(pattern: rule.pattern, url: url) {
                return .reject
            }
        }
        return nil
    }

    /// Check if a URL matches any redirect rule.
    /// Returns `.redirect(target)` if matched, or nil.
    public func matchRedirect(url: String) -> RewriteRule.RewriteAction? {
        for rule in rules where rule.enabled {
            if case .redirect(let target) = rule.action,
               matches(pattern: rule.pattern, url: url) {
                return .redirect(target)
            }
        }
        return nil
    }

    /// Get all applicable header modifications for a URL.
    /// Returns array of (key, value) pairs to apply.
    public func headerModifications(for url: String, phase: HeaderPhase = .request) -> [(String, String)] {
        var mods: [(String, String)] = []
        for rule in rules where rule.enabled {
            switch rule.action {
            case .modifyHeader(let key, let value) where phase == .request:
                if matches(pattern: rule.pattern, url: url) {
                    mods.append((key, value))
                }
            case .modifyResponseHeader(let key, let value) where phase == .response:
                if matches(pattern: rule.pattern, url: url) {
                    mods.append((key, value))
                }
            default:
                break
            }
        }
        return mods
    }

    public enum HeaderPhase {
        case request
        case response
    }

    // MARK: - Pattern Matching

    /// Simple regex-based URL matching.
    /// Supports:
    /// - Plain substring: `example.com` matches URLs containing `example.com`
    /// - Regex patterns: `^https?://.*\.example\.com/.*` uses NSRegularExpression
    private func matches(pattern: String, url: String) -> Bool {
        // Try regex first
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if regex.firstMatch(in: url, options: [], range: range) != nil {
                return true
            }
        }
        // Fallback: plain substring match
        return url.lowercased().contains(pattern.lowercased())
    }
}
