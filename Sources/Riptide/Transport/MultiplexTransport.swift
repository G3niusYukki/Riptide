import Foundation

public enum MultiplexError: Error, Sendable {
    case sessionNotFound
    case sessionClosed
    var streamError: String { String(describing: self) }
}

public actor MultiplexTransport: TransportSession {
    private let innerSession: any TransportSession
    private var streams: [UInt32: MultiplexStream]
    private var nextStreamID: UInt32 = 1
    private var recvBuffer = Data()
    private var isClosed: Bool = false

    public init(session: any TransportSession) {
        self.innerSession = session
        self.streams = [:]
        self.recvBuffer = Data()
    }

    public func openStream() -> MultiplexStream {
        let id = nextStreamID
        nextStreamID += 1
        let stream = MultiplexStream(id: id, parent: self)
        streams[id] = stream
        return stream
    }

    public func closeStream(_ id: UInt32) {
        streams.removeValue(forKey: id)
    }

    public func sendStreamData(streamID: UInt32, data: Data) async throws {
        guard streams[streamID] != nil else {
            throw MultiplexError.sessionNotFound
        }

        var frame = Data(count: 6)
        frame[0] = 0x01 // version
        frame[1] = 0x00 // type: data
        frame[2] = UInt8((streamID >> 24) & 0xFF)
        frame[3] = UInt8((streamID >> 16) & 0xFF)
        frame[4] = UInt8((streamID >> 8) & 0xFF)
        frame[5] = UInt8(streamID & 0xFF)

        var lengthData = Data(count: 2)
        let length = UInt16(data.count)
        lengthData[0] = UInt8(length >> 8)
        lengthData[1] = UInt8(length & 0xFF)

        frame.append(lengthData)
        frame.append(data)
        try await innerSession.send(frame)
    }

    public func send(_ data: Data) async throws {
        try await innerSession.send(data)
    }

    public func receive() async throws -> Data {
        try await innerSession.receive()
    }

    public func close() async {
        isClosed = true
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

    public func close() async {
        lock.withLock {
            closed = true
        }
        await parent.closeStream(id)
    }

    public var streamID: UInt32 { id }
}
