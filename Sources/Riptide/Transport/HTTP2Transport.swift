import Foundation
import Network

/// HTTP/2 transport using URLSession with HTTP/2 framing.
/// Wraps a URLSessionStreamTask as TransportSession.
public final class HTTP2TransportSession: TransportSession, @unchecked Sendable {
    private let session: URLSession
    private let streamTask: URLSessionStreamTask

    public init(session: URLSession, streamTask: URLSessionStreamTask) {
        self.session = session
        self.streamTask = streamTask
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            streamTask.write(data, timeout: 15) { error in
                if let error {
                    continuation.resume(throwing: TransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            streamTask.readData(ofMinLength: 1, maxLength: 65536, timeout: 15, completionHandler: { data, _, error in
                if let error {
                    continuation.resume(throwing: TransportError.receiveFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            })
        }
    }

    public func close() async {
        streamTask.cancel()
        session.finishTasksAndInvalidate()
    }
}

/// TransportDialer that opens HTTP/2 connections using URLSession.
public struct HTTP2TransportDialer: TransportDialer {
    public init() {}

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let sniHost = node.sni ?? node.server
        guard let _ = URL(string: "https://\(sniHost):\(node.port)") else {
            throw TransportError.dialFailed("invalid URL for h2 transport")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // URLSession auto-negotiates HTTP/2 when the server supports it via ALPN

        let session = URLSession(configuration: config)
        let streamTask = session.streamTask(withHostName: sniHost, port: node.port)

        return HTTP2TransportSession(session: session, streamTask: streamTask)
    }
}
