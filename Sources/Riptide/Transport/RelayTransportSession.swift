import Foundation

/// A `TransportSession` actor that forwards all traffic through an inner (upstream) session.
/// Used when a relay/proxy-chain node is the entry point: the client connects to the relay
/// node, and all data is tunneled through the inner connection to the next hop.
///
/// ```text
/// client  →  relaySession  →  inner session  →  next hop  →  …  →  target
/// ```
public actor RelayTransportSession: TransportSession {
    /// The inner session that carries traffic toward the next hop / target.
    private let inner: any TransportSession

    public init(inner: any TransportSession) {
        self.inner = inner
    }

    /// Forwards data to the upstream (inner) session.
    public func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    /// Returns data received from the upstream (inner) session.
    public func receive() async throws -> Data {
        try await inner.receive()
    }

    /// Closes both the relay wrapper and the inner session.
    public func close() async {
        await inner.close()
    }
}
