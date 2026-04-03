import Foundation
import Network

public final class UDPDNSClient: Sendable {
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
        let requestData = try queryMsg.encode()

        guard let port = NWEndpoint.Port(rawValue: serverPort) else {
            throw DNSError.serverError("invalid port")
        }
        let connection = NWConnection(host: NWEndpoint.Host(serverHost), port: port, using: .udp)

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
        let result: Data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            cont.resume(throwing: DNSError.serverError(String(describing: error)))
                            return
                        }
                    })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                        if let error {
                            cont.resume(throwing: DNSError.serverError(String(describing: error)))
                        } else {
                            cont.resume(returning: data ?? Data())
                        }
                    }
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
            connection.cancel()
            return first
        }

        guard !result.isEmpty else {
            throw DNSError.noRecords
        }

        return try DNSMessage.parse(result)
    }
}
