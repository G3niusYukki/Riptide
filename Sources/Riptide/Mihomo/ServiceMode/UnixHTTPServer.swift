import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Errors raised by `UnixHTTPServer`.
public enum UnixHTTPServerError: Error, Equatable, Sendable {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case pathTooLong
}

/// A minimal HTTP/1.1 server over a Unix domain socket.
///
/// This is the transport layer of Riptide's mihomo service mode, mirroring
/// Clash Verge's `clash-verge-service` (an HTTP IPC server on a Unix socket,
/// implemented there with Rust's `kode-bridge` + `interprocess`).
///
/// Concurrency model: `start()` spawns one dedicated accept thread; each
/// accepted connection is dispatched to a Task for async handling. Peer
/// (client) credentials are captured at accept time via `LOCAL_PEERCRED` and
/// vetted by `peerAcceptor` before any request is parsed, which lets the
/// root daemon restrict who may command it.
public final class UnixHTTPServer: @unchecked Sendable {

    /// Handles one request and produces the response.
    public typealias Handler = @Sendable (_ request: UnixHTTPRequest) async -> UnixHTTPResponse

    /// Vets a connecting peer's effective UID (captured via `LOCAL_PEERCRED`).
    /// Returning false closes the connection before any bytes are parsed.
    public typealias PeerAcceptor = @Sendable (_ peerUID: UInt32) -> Bool

    private let socketPath: String
    private let handler: Handler
    private let peerAcceptor: PeerAcceptor
    private let stateLock = NSLock()
    private var listenFD: Int32 = -1
    private var stopped = false

    /// Creates a server bound (on `start()`) to `socketPath`.
    /// - Parameters:
    ///   - socketPath: Unix socket file path. A stale socket file at this
    ///     path is removed on start.
    ///   - peerAcceptor: credential gate evaluated per connection. The
    ///     default accepts every peer (tests, user-owned daemons).
    ///   - handler: routes requests to responses.
    public init(
        socketPath: String,
        peerAcceptor: @escaping PeerAcceptor = { _ in true },
        handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        self.peerAcceptor = peerAcceptor
        self.handler = handler
    }

    /// True while the server loop is running.
    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listenFD >= 0 && !stopped
    }

    /// Binds, listens, chmods the socket world-read/write (the daemon runs as
    /// root while the GUI runs as a console user; authorization is enforced
    /// by `peerAcceptor`, not by socket permissions), and starts accepting.
    public func start() throws {
        let parent = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )
        // A leftover socket file from a previous run would make bind fail.
        try? FileManager.default.removeItem(atPath: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixHTTPServerError.socketCreationFailed(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout<sockaddr_un>.size - 1 else {
            close(fd)
            throw UnixHTTPServerError.pathTooLong
        }
        let sunPathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
            destination[pathBytes.count] = 0
        }
        let addressLength = socklen_t(sunPathOffset + pathBytes.count + 1)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPointer in
                bind(fd, sockPointer, addressLength)
            }
        }
        guard bindResult == 0 else {
            let error = errno
            close(fd)
            throw UnixHTTPServerError.bindFailed(error)
        }
        guard listen(fd, 16) == 0 else {
            let error = errno
            close(fd)
            throw UnixHTTPServerError.listenFailed(error)
        }
        // The daemon binds as root; make the socket reachable by non-root
        // peers. `peerAcceptor` is the real authorization boundary.
        chmod(socketPath, mode_t(0o666))

        stateLock.lock()
        listenFD = fd
        stopped = false
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.acceptLoop(listenFD: fd)
        }
        thread.name = "riptide-unix-http-accept"
        thread.start()
    }

    /// Stops accepting, closes the listener, and removes the socket file.
    /// In-flight connections finish their current exchange.
    public func stop() {
        stateLock.lock()
        stopped = true
        let fd = listenFD
        listenFD = -1
        stateLock.unlock()
        if fd >= 0 {
            close(fd)
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Private

    private func acceptLoop(listenFD: Int32) {
        while true {
            let client = accept(listenFD, nil, nil)
            stateLock.lock()
            let isStopped = stopped
            stateLock.unlock()
            guard !isStopped else {
                if client >= 0 { close(client) }
                return
            }
            guard client >= 0 else {
                // EINVAL/EBADF: listener was closed by stop().
                if errno == EINVAL || errno == EBADF { return }
                continue
            }
            guard peerUID(fd: client).map(peerAcceptor) ?? false else {
                close(client)
                continue
            }
            Task { [weak self] in
                await self?.handleConnection(client)
            }
        }
    }

    private func handleConnection(_ fd: Int32) async {
        defer { close(fd) }
        // Bound how long a slow/stuck peer can pin a handler task.
        setTimeouts(fd: fd, receiveSeconds: 15, sendSeconds: 15)
        guard let request = UnixHTTPRequest.read(from: fd) else {
            let response = UnixHTTPResponse.error("malformed request", status: 400)
            _ = UnixHTTP.sendAll(fd: fd, data: response.serialized())
            return
        }
        let response = await handler(request)
        _ = UnixHTTP.sendAll(fd: fd, data: response.serialized())
    }

    /// Effective UID of the connected peer, or nil when unavailable.
    private func peerUID(fd: Int32) -> UInt32? {
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        let result = withUnsafeMutablePointer(to: &credentials) { pointer in
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, pointer, &length)
        }
        guard result == 0, credentials.cr_version == XUCRED_VERSION else { return nil }
        return credentials.cr_uid
    }

    private func setTimeouts(fd: Int32, receiveSeconds: UInt32, sendSeconds: UInt32) {
        var receiveTimeout = timeval(tv_sec: time_t(receiveSeconds), tv_usec: 0)
        var sendTimeout = timeval(tv_sec: time_t(sendSeconds), tv_usec: 0)
        withUnsafeMutablePointer(to: &receiveTimeout) { pointer in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }
        withUnsafeMutablePointer(to: &sendTimeout) { pointer in
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }
    }
}
