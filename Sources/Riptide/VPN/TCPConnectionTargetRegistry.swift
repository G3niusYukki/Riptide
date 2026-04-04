import Foundation

/// Registers and tracks the mapping between TCP connection 4-tuples
/// and their logical routing information (target + proxy node).
///
/// When the TUN stack sees a new SYN, the engine determines where the connection
/// is trying to go and which proxy to use (via the RuleEngine in LiveTunnelRuntime).
/// This registry remembers that mapping so subsequent data packets can be forwarded.
public actor TCPConnectionTargetRegistry {

    // MARK: - Types

    /// Routing metadata for a TCP connection.
    public struct Entry: Sendable {
        public let target: ConnectionTarget
        public let proxyNode: ProxyNode
        public let createdAt: ContinuousClock.Instant

        public init(target: ConnectionTarget, proxyNode: ProxyNode) {
            self.target = target
            self.proxyNode = proxyNode
            self.createdAt = ContinuousClock.now
        }
    }

    // MARK: - State

    private var entries: [TCPConnectionID: Entry] = [:]
    private let maxEntries: Int

    // MARK: - Init

    public init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
    }

    // MARK: - Public

    /// Register routing metadata for a connection.
    /// Returns `false` if the registry is full.
    @discardableResult
    public func register(id: TCPConnectionID, target: ConnectionTarget, proxyNode: ProxyNode) -> Bool {
        guard entries.count < maxEntries else { return false }
        entries[id] = Entry(target: target, proxyNode: proxyNode)
        return true
    }

    /// Look up the entry for a connection.
    public func lookup(id: TCPConnectionID) -> Entry? {
        entries[id]
    }

    /// Remove a connection entry.
    public func remove(id: TCPConnectionID) {
        entries.removeValue(forKey: id)
    }

    /// Return the count of registered entries.
    public var count: Int {
        entries.count
    }
}
