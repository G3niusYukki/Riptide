import Foundation

/// A transport wrapper that returns already-read bytes before reading from its
/// underlying session.
public final class PrebufferedTransportSession: TransportSession, @unchecked Sendable {
    private let inner: any TransportSession
    private let lock = NSLock()
    private var prefix: Data?

    public init(prefix: Data, inner: any TransportSession) {
        self.prefix = prefix.isEmpty ? nil : prefix
        self.inner = inner
    }

    public func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    public func receive() async throws -> Data {
        lock.lock()
        if let buffered = prefix {
            prefix = nil
            lock.unlock()
            return buffered
        }
        lock.unlock()

        return try await inner.receive()
    }

    public func close() async {
        await inner.close()
    }
}
