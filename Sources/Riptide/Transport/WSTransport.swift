import Foundation

// WSTaskBox wraps URLSessionWebSocketTask which is not Sendable.
// URLSessionWebSocketTask is internally reference-counted and safe to use
// from a single actor, but the compiler cannot prove this.
private final class WSTaskBox: @unchecked Sendable {
    let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }
}

public actor WSTransportSession: TransportSession {
    private let taskBox: WSTaskBox
    private var closed = false

    fileprivate init(taskBox: WSTaskBox) {
        self.taskBox = taskBox
        self.closed = false
    }

    public func send(_ data: Data) async throws {
        guard !closed else {
            throw TransportError.sendFailed("session is closed")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            taskBox.task.send(.data(data)) { error in
                if let error {
                    continuation.resume(throwing: TransportError.sendFailed(String(describing: error)))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    public func receive() async throws -> Data {
        guard !closed else {
            throw TransportError.receiveFailed("session is closed")
        }
        return try await withCheckedThrowingContinuation { continuation in
            taskBox.task.receive { result in
                switch result {
                case .success(let message):
                    let data: Data
                    switch message {
                    case .data(let d):
                        data = d
                    case .string(let s):
                        data = Data(s.utf8)
                    @unknown default:
                        continuation.resume(throwing: TransportError.receiveFailed("unknown WebSocket message variant"))
                        return
                    }
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: TransportError.receiveFailed(String(describing: error)))
                }
            }
        }
    }

    public func close() async {
        closed = true
        taskBox.task.cancel(with: .normalClosure, reason: nil)
    }
}

public struct WSTransportDialer: TransportDialer {
    public init() {}

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = node.wsHost ?? node.server
        let path = node.wsPath ?? "/"
        let scheme = node.port == 443 ? "wss" : "ws"
        let urlString = "\(scheme)://\(host):\(node.port)\(path)"

        guard let url = URL(string: urlString) else {
            throw TransportError.dialFailed("invalid WebSocket URL: \(urlString)")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        return WSTransportSession(taskBox: WSTaskBox(task: task))
    }
}
