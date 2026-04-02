import Foundation

public enum VLESSError: Error, Equatable, Sendable {
    case invalidUUID
    case invalidRequest
    case missingTLS
}

public actor VLESSStream: Sendable {
    private let session: any TransportSession
    private let uuid: UUID
    private var recvBuffer = Data()

    public init(session: any TransportSession, uuid: UUID) {
        self.session = session
        self.uuid = uuid
    }

    public func connect(to target: ConnectionTarget, flow: String? = nil) async throws {
        var request = Data()
        request.append(0) // version
        request.append(contentsOf: uuid.uuid)

        var addons = Data()
        if let flow {
            let flowData = Data(flow.utf8)
            addons.append(UInt8(flowData.count))
            addons.append(flowData)
        } else {
            addons.append(0)
        }
        request.append(UInt8(addons.count))
        request.append(addons)

        request.append(try encodeVLESSTarget(target))

        try await session.send(request)
    }

    public func send(_ data: Data) async throws {
        try await session.send(data)
    }

    public func receive() async throws -> Data {
        let data = try await session.receive()
        return data
    }

    public func close() async {
        await session.close()
    }

    private func encodeVLESSTarget(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        if let ipv4 = parseIPv4(target.host) {
            data.append(1) // ATYP IPv4
            data.append(contentsOf: ipv4)
        } else if target.host.contains(":") {
            data.append(3) // ATYP domain for IPv6 string
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        } else {
            data.append(2) // ATYP Domain
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        }
        let port = UInt16(target.port)
        data.append(UInt8(port >> 8))
        data.append(UInt8(port & 0xFF))
        return data
    }

    private func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        return parts.compactMap { UInt8(String($0)) }
    }
}
