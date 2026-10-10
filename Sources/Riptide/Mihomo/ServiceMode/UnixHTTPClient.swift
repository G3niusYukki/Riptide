import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Errors raised by `UnixHTTPClient`.
public enum UnixHTTPClientError: Error, Equatable, Sendable {
    case connectFailed(String)
    case sendFailed
    case responseUnreadable
    case timeout
}

/// A minimal HTTP/1.1 client over a Unix domain socket.
///
/// `URLSession` cannot speak HTTP over Unix sockets, so service mode uses
/// this small POSIX-socket client — the Swift counterpart of the Rust
/// `interprocess`-based client Clash Verge's GUI uses to reach its root
/// service.
public struct UnixHTTPClient: Sendable {

    private let socketPath: String
    private let timeoutSeconds: UInt32

    /// - Parameters:
    ///   - socketPath: Unix socket file path of the server.
    ///   - timeoutSeconds: per-socket send/receive timeout.
    public init(socketPath: String, timeoutSeconds: UInt32 = 5) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    /// Performs one request/response exchange over a fresh connection
    /// (HTTP/1.1 without keep-alive, matching the server).
    public func send(_ request: UnixHTTPRequest) throws -> UnixHTTPResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixHTTPClientError.connectFailed("socket() failed: \(errno)")
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout<sockaddr_un>.size - 1 else {
            throw UnixHTTPClientError.connectFailed("socket path too long")
        }
        let sunPathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
            destination[pathBytes.count] = 0
        }
        let addressLength = socklen_t(sunPathOffset + pathBytes.count + 1)

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPointer in
                connect(fd, sockPointer, addressLength)
            }
        }
        guard connectResult == 0 else {
            throw UnixHTTPClientError.connectFailed(
                "connect(\(socketPath)) failed: \(String(cString: strerror(errno)))"
            )
        }

        var receiveTimeout = timeval(tv_sec: time_t(timeoutSeconds), tv_usec: 0)
        var sendTimeout = timeval(tv_sec: time_t(timeoutSeconds), tv_usec: 0)
        withUnsafeMutablePointer(to: &receiveTimeout) { pointer in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }
        withUnsafeMutablePointer(to: &sendTimeout) { pointer in
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }

        guard UnixHTTP.sendAll(fd: fd, data: request.serialized()) else {
            throw UnixHTTPClientError.sendFailed
        }
        guard let response = UnixHTTPResponse.read(from: fd) else {
            throw UnixHTTPClientError.responseUnreadable
        }
        return response
    }
}
