import Foundation
import Network

public final class TCPDNSClient: Sendable {
    private let serverHost: String
    private let serverPort: UInt16
    private let timeout: Duration

    public init(serverHost: String = "8.8.8.8", serverPort: UInt16 = 53, timeout: Duration = .seconds(5)) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.timeout = timeout
    }

    public func query(name: String, type: DNSRecordType = .a, id: UInt16 = 0) async throws -> DNSMessage {
        let queryMsg = DNSMessage.buildQuery(name: name, type: type, id: id)
        let requestBytes = try queryMsg.encode()

        var packet = Data(count: 2)
        packet[0] = UInt8((requestBytes.count >> 8) & 0xFF)
        packet[1] = UInt8(requestBytes.count & 0xFF)
        packet.append(requestBytes)

        guard let port = NWEndpoint.Port(rawValue: serverPort) else {
            throw DNSError.serverError("invalid port")
        }
        let connection = NWConnection(host: NWEndpoint.Host(serverHost), port: port, using: .tcp)

        defer { connection.cancel() }

        // Await connection readiness, handling all terminal states.
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
                    // Already cancelled — do not resume.
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

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
        let timeoutSeconds = self.timeout
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
            group.addTask {
                try await Task.sleep(for: timeoutSeconds)
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
            group.addTask {
                try await Task.sleep(for: timeoutSeconds)
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
}
