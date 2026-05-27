import Foundation
import Security

/// A TLS layer that can be placed on top of any `TransportSession`.
///
/// Network.framework configures TLS only when an `NWConnection` is created. MITM
/// needs TLS after the HTTP CONNECT tunnel is already established, so this
/// adapter uses SecureTransport's callback I/O over Riptide's byte-stream
/// transport abstraction.
public final class MITMTLSSession: TransportSession, @unchecked Sendable {
    private let context: SSLContext
    private let io: MITMTLSIO
    private let contextLock = NSLock()
    private let handshakeGate = MITMTLSHandshakeGate()

    private init(context: SSLContext, io: MITMTLSIO) {
        self.context = context
        self.io = io
    }

    public static func server(over session: any TransportSession, identity: MITMServerIdentity) throws -> MITMTLSSession {
        let tlsSession = try configuredSession(over: session, role: .server)
        let certificateChain: [Any] = [identity.identity]
        try throwIfFailed(
            RiptideSSLSetCertificate(tlsSession.context, certificateChain as CFArray),
            operation: "set server certificate"
        )
        return tlsSession
    }

    public static func client(
        over session: any TransportSession,
        serverName: String,
        verifyServerCertificate: Bool = true
    ) throws -> MITMTLSSession {
        let tlsSession = try configuredSession(over: session, role: .client)
        try serverName.withCString { pointer in
            try throwIfFailed(
                RiptideSSLSetPeerDomainName(tlsSession.context, pointer, strlen(pointer)),
                operation: "set peer domain name"
            )
        }

        if verifyServerCertificate == false {
            try throwIfFailed(
                RiptideSSLSetSessionOption(
                    tlsSession.context,
                    try MITMTLSConstants.breakOnServerAuth(),
                    true
                ),
                operation: "disable automatic server certificate verification"
            )
        }

        return tlsSession
    }

    public func send(_ data: Data) async throws {
        guard data.isEmpty == false else { return }
        try await ensureHandshake()

        var offset = 0
        while offset < data.count {
            var processed = 0
            let remaining = data.count - offset
            let status = withContextLock {
                data.withUnsafeBytes { rawBuffer -> OSStatus in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return errSecParam
                    }
                    return RiptideSSLWrite(
                        context,
                        baseAddress.advanced(by: offset),
                        remaining,
                        &processed
                    )
                }
            }

            if processed > 0 {
                offset += processed
            }

            switch status {
            case errSecSuccess:
                if processed == 0 {
                    throw MITMError.tlsWriteFailed(status)
                }
            case errSSLWouldBlock:
                try await io.waitForReadable()
            default:
                throw MITMError.tlsWriteFailed(status)
            }
        }
    }

    public func receive() async throws -> Data {
        try await ensureHandshake()

        while true {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var processed = 0
            let capacity = buffer.count
            let status = withContextLock {
                buffer.withUnsafeMutableBytes { rawBuffer -> OSStatus in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return errSecParam
                    }
                    return RiptideSSLRead(context, baseAddress, capacity, &processed)
                }
            }

            if processed > 0 {
                return Data(buffer.prefix(processed))
            }

            switch status {
            case errSecSuccess:
                return Data()
            case errSSLWouldBlock:
                try await io.waitForReadable()
            case errSSLClosedGraceful, errSSLClosedNoNotify:
                return Data()
            default:
                throw MITMError.tlsReadFailed(status)
            }
        }
    }

    public func close() async {
        _ = withContextLock {
            RiptideSSLClose(context)
        }
        io.close()
        await io.closeUnderlying()
    }

    private static func configuredSession(
        over session: any TransportSession,
        role: MITMTLSRole
    ) throws -> MITMTLSSession {
        guard let context = RiptideSSLCreateContext(nil, try role.protocolSide(), try MITMTLSConstants.streamType()) else {
            throw MITMError.tlsContextCreationFailed
        }

        let io = MITMTLSIO(session: session)
        try throwIfFailed(
            RiptideSSLSetIOFuncs(context, mitmTLSReadCallback, mitmTLSWriteCallback),
            operation: "set TLS I/O callbacks"
        )
        try throwIfFailed(
            RiptideSSLSetConnection(context, Unmanaged.passUnretained(io).toOpaque()),
            operation: "set TLS connection context"
        )
        try throwIfFailed(
            RiptideSSLSetProtocolVersionMin(context, try MITMTLSConstants.tlsProtocol12()),
            operation: "set minimum TLS version"
        )

        return MITMTLSSession(context: context, io: io)
    }

    private static func throwIfFailed(_ status: OSStatus, operation: String) throws {
        guard status == errSecSuccess else {
            throw MITMError.tlsConfigurationFailed(operation, status)
        }
    }

    private func ensureHandshake() async throws {
        try await handshakeGate.ensure {
            try await self.performHandshake()
        }
    }

    private func performHandshake() async throws {
        while true {
            let status = withContextLock {
                RiptideSSLHandshake(context)
            }

            switch status {
            case errSecSuccess:
                return
            case errSSLWouldBlock:
                try await io.waitForReadable()
            case errSSLPeerAuthCompleted:
                continue
            default:
                throw MITMError.tlsHandshakeFailed(status)
            }
        }
    }

    private func withContextLock<T>(_ operation: () -> T) -> T {
        contextLock.lock()
        defer { contextLock.unlock() }
        return operation()
    }
}

private actor MITMTLSHandshakeGate {
    private var task: Task<Void, Error>?

    func ensure(_ operation: @Sendable @escaping () async throws -> Void) async throws {
        if let task {
            try await task.value
            return
        }

        let task = Task {
            try await operation()
        }
        self.task = task
        try await task.value
    }
}

private enum MITMTLSRole {
    case server
    case client

    func protocolSide() throws -> SSLProtocolSide {
        let rawValue: Int32 = switch self {
        case .server: 0
        case .client: 1
        }
        guard let side = SSLProtocolSide(rawValue: rawValue) else {
            throw MITMError.tlsConfigurationFailed("resolve TLS role", errSecParam)
        }
        return side
    }
}

private enum MITMTLSConstants {
    static func streamType() throws -> SSLConnectionType {
        guard let value = SSLConnectionType(rawValue: 0) else {
            throw MITMError.tlsConfigurationFailed("resolve stream connection type", errSecParam)
        }
        return value
    }

    static func breakOnServerAuth() throws -> SSLSessionOption {
        guard let value = SSLSessionOption(rawValue: 0) else {
            throw MITMError.tlsConfigurationFailed("resolve server auth option", errSecParam)
        }
        return value
    }

    static func tlsProtocol12() throws -> SSLProtocol {
        guard let value = SSLProtocol(rawValue: 8) else {
            throw MITMError.tlsConfigurationFailed("resolve TLS 1.2 protocol version", errSecParam)
        }
        return value
    }
}

private final class MITMTLSIO: @unchecked Sendable {
    private let session: any TransportSession
    private let lock = NSLock()
    private var inbound = Data()
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var closed = false
    private var receiveError: Error?
    private var receiveTask: Task<Void, Never>?

    init(session: any TransportSession) {
        self.session = session
        self.receiveTask = Task {
            await self.receiveLoop()
        }
    }

    func read(into data: UnsafeMutableRawPointer, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        guard inbound.isEmpty == false else {
            dataLength.pointee = 0
            if receiveError != nil {
                return errSSLClosedAbort
            }
            return closed ? errSSLClosedGraceful : errSSLWouldBlock
        }

        let count = min(dataLength.pointee, inbound.count)
        let bytes = inbound.prefix(count)
        bytes.withUnsafeBytes { buffer in
            if let source = buffer.baseAddress {
                data.copyMemory(from: source, byteCount: count)
            }
        }
        inbound.removeFirst(count)
        dataLength.pointee = count
        return errSecSuccess
    }

    func write(_ data: UnsafeRawPointer, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
        let requestedLength = dataLength.pointee
        guard requestedLength > 0 else {
            return errSecSuccess
        }

        let payload = Data(bytes: data, count: requestedLength)
        let completion = MITMTLSWriteCompletion()
        Task {
            do {
                try await session.send(payload)
                completion.complete(errSecSuccess)
            } catch {
                completion.complete(errSSLClosedAbort)
            }
        }

        let status = completion.wait()
        if status != errSecSuccess {
            dataLength.pointee = 0
            return status
        }

        dataLength.pointee = requestedLength
        return errSecSuccess
    }

    func waitForReadable() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if inbound.isEmpty == false || closed {
                lock.unlock()
                continuation.resume(returning: ())
                return
            }
            if let receiveError {
                lock.unlock()
                continuation.resume(throwing: MITMError.tlsIOFailed(String(describing: receiveError)))
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func close() {
        receiveTask?.cancel()
        finishReceiveLoop(error: nil)
    }

    func closeUnderlying() async {
        await session.close()
    }

    private func receiveLoop() async {
        while Task.isCancelled == false {
            do {
                let chunk = try await session.receive()
                guard chunk.isEmpty == false else {
                    finishReceiveLoop(error: nil)
                    return
                }
                appendInbound(chunk)
            } catch {
                finishReceiveLoop(error: error)
                return
            }
        }
    }

    private func appendInbound(_ data: Data) {
        lock.lock()
        inbound.append(data)
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.resume(returning: ())
        }
    }

    private func finishReceiveLoop(error: Error?) {
        lock.lock()
        if let error {
            receiveError = error
        } else {
            closed = true
        }
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            if let error {
                waiter.resume(throwing: MITMError.tlsIOFailed(String(describing: error)))
            } else {
                waiter.resume(returning: ())
            }
        }
    }
}

private final class MITMTLSWriteCompletion: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var status: OSStatus?

    func complete(_ status: OSStatus) {
        lock.lock()
        self.status = status
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> OSStatus {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return status ?? errSSLClosedAbort
    }
}

private func mitmTLSReadCallback(
    _ connection: SSLConnectionRef,
    _ data: UnsafeMutableRawPointer,
    _ dataLength: UnsafeMutablePointer<Int>
) -> OSStatus {
    let io = Unmanaged<MITMTLSIO>.fromOpaque(connection).takeUnretainedValue()
    return io.read(into: data, dataLength: dataLength)
}

private func mitmTLSWriteCallback(
    _ connection: SSLConnectionRef,
    _ data: UnsafeRawPointer,
    _ dataLength: UnsafeMutablePointer<Int>
) -> OSStatus {
    let io = Unmanaged<MITMTLSIO>.fromOpaque(connection).takeUnretainedValue()
    return io.write(data, dataLength: dataLength)
}

@_silgen_name("SSLCreateContext")
private func RiptideSSLCreateContext(
    _ alloc: CFAllocator?,
    _ protocolSide: SSLProtocolSide,
    _ connectionType: SSLConnectionType
) -> SSLContext?

@_silgen_name("SSLSetIOFuncs")
private func RiptideSSLSetIOFuncs(
    _ context: SSLContext,
    _ readFunc: SSLReadFunc,
    _ writeFunc: SSLWriteFunc
) -> OSStatus

@_silgen_name("SSLSetConnection")
private func RiptideSSLSetConnection(
    _ context: SSLContext,
    _ connection: SSLConnectionRef?
) -> OSStatus

@_silgen_name("SSLSetProtocolVersionMin")
private func RiptideSSLSetProtocolVersionMin(
    _ context: SSLContext,
    _ minVersion: SSLProtocol
) -> OSStatus

@_silgen_name("SSLSetCertificate")
private func RiptideSSLSetCertificate(
    _ context: SSLContext,
    _ certRefs: CFArray?
) -> OSStatus

@_silgen_name("SSLSetPeerDomainName")
private func RiptideSSLSetPeerDomainName(
    _ context: SSLContext,
    _ peerName: UnsafePointer<CChar>?,
    _ peerNameLen: Int
) -> OSStatus

@_silgen_name("SSLSetSessionOption")
private func RiptideSSLSetSessionOption(
    _ context: SSLContext,
    _ option: SSLSessionOption,
    _ value: Bool
) -> OSStatus

@_silgen_name("SSLHandshake")
private func RiptideSSLHandshake(_ context: SSLContext) -> OSStatus

@_silgen_name("SSLRead")
private func RiptideSSLRead(
    _ context: SSLContext,
    _ data: UnsafeMutableRawPointer?,
    _ dataLength: Int,
    _ processed: UnsafeMutablePointer<Int>
) -> OSStatus

@_silgen_name("SSLWrite")
private func RiptideSSLWrite(
    _ context: SSLContext,
    _ data: UnsafeRawPointer?,
    _ dataLength: Int,
    _ processed: UnsafeMutablePointer<Int>
) -> OSStatus

@_silgen_name("SSLClose")
private func RiptideSSLClose(_ context: SSLContext) -> OSStatus
