import Foundation

public enum MultiplexFrameType: UInt8, Sendable {
    case data = 0x00
    case syn = 0x01
    case fin = 0x02
    case rst = 0x03
}

public enum MultiplexError: Error, Sendable {
    case sessionNotFound
    case sessionClosed
    case streamClosed
    case protocolError(String)
}

public actor MultiplexTransport: TransportSession {
    private let innerSession: any TransportSession
    private var streams: [UInt32: MultiplexStream] = [:]
    private var nextStreamID: UInt32 = 1
    private var isClosed: Bool = false
    /// Non-actor accessor for the closed flag, used from the receive task.
    private func checkIsClosed() -> Bool { isClosed }
    private var receiveTask: Task<Void, Never>?

    public init(session: any TransportSession) {
        self.innerSession = session
    }

    public func openStream() -> MultiplexStream {
        let id = nextStreamID
        nextStreamID += 1
        let stream = MultiplexStream(id: id, parent: self)
        streams[id] = stream
        return stream
    }

    public func closeStream(_ id: UInt32) {
        streams[id]?.notifyClosed()
        streams.removeValue(forKey: id)
    }

    public func sendStreamData(streamID: UInt32, data: Data) async throws {
        guard streams[streamID] != nil else {
            throw MultiplexError.sessionNotFound
        }
        guard data.count <= Int(UInt16.max) else {
            throw MultiplexError.protocolError("payload exceeds max frame size (65535 bytes)")
        }

        var frame = Data(capacity: 8 + data.count)
        frame.append(0x01) // version
        frame.append(MultiplexFrameType.data.rawValue)
        frame.append(UInt8((streamID >> 24) & 0xFF))
        frame.append(UInt8((streamID >> 16) & 0xFF))
        frame.append(UInt8((streamID >> 8) & 0xFF))
        frame.append(UInt8(streamID & 0xFF))

        let length = UInt16(data.count)
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xFF))
        frame.append(data)

        try await innerSession.send(frame)
    }

    private func sendControlFrame(type: MultiplexFrameType, streamID: UInt32) async {
        var frame = Data(count: 8)
        frame[0] = 0x01
        frame[1] = type.rawValue
        frame[2] = UInt8((streamID >> 24) & 0xFF)
        frame[3] = UInt8((streamID >> 16) & 0xFF)
        frame[4] = UInt8((streamID >> 8) & 0xFF)
        frame[5] = UInt8(streamID & 0xFF)
        frame[6] = 0
        frame[7] = 0 // length = 0
        try? await innerSession.send(frame)
    }

    public func send(_ data: Data) async throws {
        try await innerSession.send(data)
    }

    /// Start the receive loop. Must be called after creating streams.
    public func startReceiving() {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            guard let self else { return }
            var buffer = Data()
            while !Task.isCancelled {
                let closed = await self.checkIsClosed()
                if closed { break }
                do {
                    let chunk = try await self.innerSession.receive()
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    buffer = await self.processFrames(from: buffer)
                } catch {
                    break
                }
            }
        }
    }

    private func processFrames(from buffer: Data) -> Data {
        var remaining = buffer
        while remaining.count >= 8 {
            let version = remaining[0]
            guard version == 0x01 else {
                // Skip unknown version
                remaining = Data()
                break
            }
            let type = remaining[1]
            let streamID = UInt32(remaining[2]) << 24 |
                           UInt32(remaining[3]) << 16 |
                           UInt32(remaining[4]) << 8 |
                           UInt32(remaining[5])
            let length = Int(UInt16(remaining[6]) << 8 | UInt16(remaining[7]))

            guard remaining.count >= 8 + length else {
                break // Incomplete frame
            }

            let frameData = remaining.subdata(in: 8..<8 + length)
            remaining = remaining.subdata(in: 8 + length..<remaining.count)

            handleFrame(type: type, streamID: streamID, data: frameData)
        }
        return remaining
    }

    private func handleFrame(type: UInt8, streamID: UInt32, data: Data) {
        guard let frameType = MultiplexFrameType(rawValue: type) else { return }

        switch frameType {
        case .data:
            streams[streamID]?.deliverData(data)
        case .fin:
            let stream = streams.removeValue(forKey: streamID)
            stream?.notifyClosed()
        case .rst:
            let stream = streams.removeValue(forKey: streamID)
            stream?.notifyClosed()
        case .syn:
            break // Server-initiated streams not supported yet
        }
    }

    public func receive() async throws -> Data {
        try await innerSession.receive()
    }

    public func close() async {
        isClosed = true
        receiveTask?.cancel()
        receiveTask = nil
        for (_, stream) in streams {
            stream.notifyClosed()
        }
        streams.removeAll()
        await innerSession.close()
    }
}

public final class MultiplexStream: @unchecked Sendable {
    public let id: UInt32
    private let parent: MultiplexTransport
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false
    private var waitingContinuation: CheckedContinuation<Data, Error>?

    init(id: UInt32, parent: MultiplexTransport) {
        self.id = id
        self.parent = parent
    }

    public func send(_ data: Data) async throws {
        try lock.withLock {
            guard !closed else { throw MultiplexError.sessionClosed }
        }
        try await parent.sendStreamData(streamID: id, data: data)
    }

    public func receive() async throws -> Data {
        while true {
            let (data, isClosed) = try lock.withLock { () -> (Data?, Bool) in
                if !buffer.isEmpty {
                    let data = buffer
                    buffer = Data()
                    return (data, self.closed)
                }
                if self.closed {
                    return (nil, true)
                }
                return (nil, false)
            }

            if let data {
                return data
            }
            if isClosed {
                throw MultiplexError.streamClosed
            }

            // Wait for data
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                lock.lock()
                if !buffer.isEmpty {
                    let data = buffer
                    buffer = Data()
                    lock.unlock()
                    continuation.resume(returning: data)
                    return
                }
                if closed {
                    lock.unlock()
                    continuation.resume(throwing: MultiplexError.streamClosed)
                    return
                }
                if waitingContinuation != nil {
                    lock.unlock()
                    continuation.resume(throwing: MultiplexError.protocolError("concurrent receive() calls are not supported"))
                    return
                }
                waitingContinuation = continuation
                lock.unlock()
            }
        }
    }

    public func close() async {
        let wasOpen = lock.withLock { () -> Bool in
            if closed { return false }
            closed = true
            return true
        }
        if wasOpen {
            await parent.closeStream(id)
        }
    }

    fileprivate func deliverData(_ data: Data) {
        lock.lock()
        if let cont = waitingContinuation {
            waitingContinuation = nil
            lock.unlock()
            cont.resume(returning: data)
        } else {
            buffer.append(data)
            lock.unlock()
        }
    }

    fileprivate func notifyClosed() {
        lock.lock()
        closed = true
        if let cont = waitingContinuation {
            waitingContinuation = nil
            lock.unlock()
            cont.resume(throwing: MultiplexError.streamClosed)
        } else {
            lock.unlock()
        }
    }

    public var streamID: UInt32 { id }
}
