import Foundation
import SwiftUI

/// Manager for proxy group operations including auto-testing and selection
public enum ProxyGroupManager {

    /// Selects the best proxy from a list based on measured delays.
    /// - Parameters:
    ///   - proxyNames: List of proxy names to consider
    ///   - delays: Dictionary of proxy name -> delay in milliseconds
    /// - Returns: The name of the best proxy, or first proxy if no delays available
    public static func selectBestProxy(from proxyNames: [String], delays: [String: Int]) -> String? {
        guard !proxyNames.isEmpty else { return nil }

        // Filter proxies that have valid delay measurements
        let measuredProxies = proxyNames.compactMap { name -> (name: String, delay: Int)? in
            guard let delay = delays[name] else { return nil }
            return (name, delay)
        }

        // If we have measured delays, pick the one with lowest delay
        if !measuredProxies.isEmpty {
            let best = measuredProxies.min { $0.delay < $1.delay }
            return best?.name
        }

        // Otherwise return the first proxy as fallback
        return proxyNames.first
    }

    /// Determines if a proxy group should be auto-tested.
    /// - Parameter group: The proxy group to check
    /// - Returns: true if the group type supports auto-testing (url-test, fallback)
    public static func shouldAutoTest(group: ProxyGroup) -> Bool {
        switch group.kind {
        case .urlTest, .fallback:
            return true
        case .select, .loadBalance:
            return false
        }
    }

    /// Returns the color representing delay status for UI display.
    /// - Parameter delayMs: Delay in milliseconds, or nil for timeout/untested
    /// - Returns: Color representing the delay status
    public static func delayStatusColor(_ delayMs: Int?) -> Color {
        guard let delay = delayMs else {
            return .gray
        }

        if delay < 100 {
            return .green
        } else if delay < 300 {
            return .yellow
        } else {
            return .red
        }
    }

    /// Returns a human-readable delay description.
    /// - Parameter delayMs: Delay in milliseconds, or nil for timeout
    /// - Returns: Formatted string like "150ms" or "timeout"
    public static func delayDescription(_ delayMs: Int?) -> String {
        guard let delay = delayMs else {
            return "timeout"
        }
        return "\(delay)ms"
    }
}
