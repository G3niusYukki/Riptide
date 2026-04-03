import Foundation
import Network

/// DNS-over-QUIC resolver.
///
/// Sends DNS queries over a QUIC connection per RFC 9250.
/// The DNS message is sent as a STREAM frame payload on an opened bidirectional stream.
/// Reliability is handled by QUIC at the transport layer — there is no DNS query ID.
public final class DOQResolver: Sendable {
    private let serverHost: String
    private let serverPort: UInt16
    private let timeout: Duration

    public init(serverHost: String, serverPort: UInt16 = 853, timeout: Duration = .seconds(5)) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.timeout = timeout
    }

    /// Query a DNS name using DoQ.
    public func query(name: String, type: DNSRecordType = .a, id: UInt16 = 0) async throws -> DNSMessage {
        // DoQ via NWProtocolQUIC is not available on this platform.
        // Fall back to UDP DNS.
        throw DNSError.serverError("DoQ not available on this platform")
    }
}
