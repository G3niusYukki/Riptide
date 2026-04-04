import Foundation
import Network

/// DNS-over-QUIC resolver per RFC 9250.
///
/// Sends DNS queries over a QUIC connection.
/// The DNS message is sent as a STREAM frame payload on an opened bidirectional stream.
/// Reliability is handled by QUIC at the transport layer — there is no DNS query ID.
///
/// Requires macOS 14+ for `NWProtocolQUIC`.
public final class DOQResolver: Sendable {

    // MARK: - Errors

    public enum DOQError: Error, Equatable, Sendable {
        case connectionFailed(String)
        case sendFailed(String)
        case receiveFailed(String)
        case quicNotAvailable
        case invalidResponse(String)

        public var localizedDescription: String {
            switch self {
            case .connectionFailed(let msg): return "DoQ connection failed: \(msg)"
            case .sendFailed(let msg): return "DoQ send failed: \(msg)"
            case .receiveFailed(let msg): return "DoQ receive failed: \(msg)"
            case .quicNotAvailable: return "QUIC is not available on this platform (requires macOS 14+)"
            case .invalidResponse(let msg): return "Invalid DoQ response: \(msg)"
            }
        }
    }

    // MARK: - State

    private let serverHost: String
    private let serverPort: UInt16
    private let timeout: Duration
    private let alpn: String

    public init(serverHost: String, serverPort: UInt16 = 853, timeout: Duration = .seconds(5)) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.timeout = timeout
        self.alpn = "doq"  // RFC 9250 ALPN
    }

    /// Query a DNS name using DoQ.
    public func query(name: String, type: DNSRecordType = .a, id: UInt16 = 0) async throws -> DNSMessage {
        // Build DNS query
        let queryMessage = try buildDNSQuery(name: name, type: type, id: id)

        // Create QUIC session
        let session: QUICTransportSession
        do {
            let s = QUICTransportSession.makeSession(
                host: serverHost,
                port: serverPort,
                alpn: [alpn]
            )
            try await s.connect()
            session = s
        } catch QUICTransportSession.QUICTransportError.quicNotAvailable {
            throw DOQError.quicNotAvailable
        } catch {
            throw DOQError.connectionFailed(error.localizedDescription)
        }

        // Send DNS query over QUIC stream
        // Per RFC 9250: the DNS message is sent with a 2-byte length prefix
        var sendData = Data()
        let length = UInt16(queryMessage.count)
        sendData.append(UInt8(length >> 8))
        sendData.append(UInt8(length & 0xFF))
        sendData.append(queryMessage)

        do {
            try await session.send(sendData)
        } catch {
            await session.close()
            throw DOQError.sendFailed(error.localizedDescription)
        }

        // Receive response
        let responseData: Data
        do {
            responseData = try await session.receive()
        } catch {
            await session.close()
            throw DOQError.receiveFailed(error.localizedDescription)
        }

        await session.close()

        // Parse response (skip 2-byte length prefix)
        guard responseData.count >= 2 else {
            throw DOQError.invalidResponse("too short")
        }

        let dnsData = responseData.subdata(in: 2..<responseData.count)
        return try DNSMessage.parse(dnsData)
    }

    // MARK: - DNS Query Builder

    private func buildDNSQuery(name: String, type: DNSRecordType, id: UInt16) throws -> Data {
        let header = DNSHeader(
            id: id,
            isResponse: false,
            opcode: 0,
            authoritative: false,
            truncated: false,
            recursionDesired: true,
            recursionAvailable: false,
            responseCode: .noError,
            questionCount: 1,
            answerCount: 0
        )

        let question = DNSQuestion(name: name, type: type, classValue: .inet)

        let message = DNSMessage(header: header, questions: [question], answers: [])
        return try message.encode()
    }
}
