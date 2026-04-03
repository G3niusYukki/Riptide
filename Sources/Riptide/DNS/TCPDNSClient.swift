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

        // Await connection readiness outside the task group (Copilot: task group is Data but ready gate returns Void)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                case .failed(let error):
                    cont.resume(throwing: DNSError.serverError(String(describing: error)))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        // Use race pattern for timeout instead of non-existent group.next(timeout:)
        let sendPacket = packet  // copy for sendability
        let sendConnection = connection
        let result: Data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    sendConnection.send(content: sendPacket, completion: .contentProcessed { error in
                        if let error {
                            cont.resume(throwing: DNSError.serverError(String(describing: error)))
                            return
                        }
                    })
                    var buffer = Data()
                    func readMore() {
                        sendConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                            if let error {
                                cont.resume(throwing: DNSError.serverError(String(describing: error)))
                                return
                            }
                            guard let data, !data.isEmpty else {
                                cont.resume(throwing: DNSError.noRecords)
                                return
                            }
                            buffer.append(data)
                            if buffer.count >= 2 {
                                let length = Int(buffer[0]) << 8 | Int(buffer[1])
                                if buffer.count >= 2 + length {
                                    cont.resume(returning: Data(buffer.dropFirst(2)))
                                    return
                                }
                            }
                            readMore()
                        }
                    }
                    readMore()
                }
            }

            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw DNSError.timeout
            }

            guard let first = try await group.next() else {
                throw DNSError.timeout
            }
            group.cancelAll()
            sendConnection.cancel()
            return first
        }

        return try DNSMessage.parse(result)
    }
}
