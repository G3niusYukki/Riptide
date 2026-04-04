import Foundation
import Network

/// Actor that sends DNS queries over DNS-over-TLS (DoT).
/// DoT uses raw TCP with TLS wrapping; the DNS query is sent as-is with a 2-byte length prefix.
public actor DOTResolver {
    private let host: String
    private let port: UInt16
    private let timeout: Duration

    public init(host: String, port: UInt16 = 853, timeout: Duration = .seconds(5)) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    /// Convenience initializer from a "host:port" address string.
    public init(address: String, timeout: Duration = .seconds(5)) throws {
        let parts = address.split(separator: ":")
        guard parts.count == 2, let portNum = UInt16(parts[1]) else {
            throw DNSError.serverError("invalid DoT address: \(address); expected host:port")
        }
        self.host = String(parts[0])
        self.port = portNum
        self.timeout = timeout
    }

    public func query(name: String, type: DNSRecordType = .a, id: UInt16 = 0) async throws -> DNSMessage {
        let queryMsg = DNSMessage.buildQuery(name: name, type: type, id: id)
        let requestBytes = try queryMsg.encode()

        // 2-byte length prefix (TCP style)
        var packet = Data(count: 2)
        packet[0] = UInt8((requestBytes.count >> 8) & 0xFF)
        packet[1] = UInt8(requestBytes.count & 0xFF)
        packet.append(requestBytes)

        let connection = try await self.makeTLSConnection()

        defer { connection.cancel() }

        // Send query
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: DNSError.serverError(String(describing: error)))
                } else {
                    cont.resume()
                }
            })
        }

        // Read 2-byte length prefix
        let lengthData = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                        if let error {
                            cont.resume(throwing: DNSError.serverError(String(describing: error)))
                        } else if let data, data.count == 2 {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(throwing: DNSError.noRecords)
                        }
                    }
                }
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw DNSError.timeout
            }
            guard let result = try await group.next() else {
                throw DNSError.timeout
            }
            group.cancelAll()
            return result
        }

        let payloadLength = Int(lengthData[0]) << 8 | Int(lengthData[1])

        // Read payload
        let payload = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: payloadLength, maximumLength: payloadLength) { data, _, _, error in
                        if let error {
                            cont.resume(throwing: DNSError.serverError(String(describing: error)))
                        } else if let data {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(throwing: DNSError.noRecords)
                        }
                    }
                }
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw DNSError.timeout
            }
            guard let result = try await group.next() else {
                throw DNSError.timeout
            }
            group.cancelAll()
            return result
        }

        return try DNSMessage.parse(payload)
    }

    private func makeTLSConnection() async throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw DNSError.serverError("invalid port: \(port)")
        }

        let connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                case .failed(let error):
                    cont.resume(throwing: DNSError.serverError(String(describing: error)))
                case .waiting(let error):
                    cont.resume(throwing: DNSError.serverError(String(describing: error)))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        return connection
    }
}
