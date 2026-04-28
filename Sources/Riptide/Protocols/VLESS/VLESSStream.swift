import Foundation
import Darwin

public enum VLESSError: Error, Equatable, Sendable {
    case invalidUUID
    case invalidRequest
    case missingTLS
}

public actor VLESSStream: Sendable {
    private let session: any TransportSession
    private let uuid: UUID
    private let reality: RealityConfig?
    private var recvBuffer = Data()
    private var versionByteConsumed = false

    public init(session: any TransportSession, uuid: UUID, reality: RealityConfig? = nil) {
        self.session = session
        self.uuid = uuid
        self.reality = reality
    }

    public func connect(to target: ConnectionTarget, flow: String? = nil) async throws {
        var request = Data()
        request.append(0) // version
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        request.append(contentsOf: uuidBytes)

        // VLESS addons are proto3-encoded VLESSSession { string flow = 1; }
        // For no flow: empty message = 0x0A 0x00 (field 1 wire type 2, length 0)
        let addons = encodeVLESSAddons(flow: flow)
        request.append(UInt8(addons.count))
        request.append(addons)

        request.append(try encodeVLESSTarget(target))

        try await session.send(request)

        // Read 1-byte version response from server
        let response = try await session.receive()
        guard !response.isEmpty else {
            throw VLESSError.invalidRequest
        }
        versionByteConsumed = true
        if response.count > 1 {
            recvBuffer = Data(response.dropFirst())
        }
    }

    public func send(_ data: Data) async throws {
        try await session.send(data)
    }

    public func receive() async throws -> Data {
        if !recvBuffer.isEmpty {
            let data = recvBuffer
            recvBuffer = Data()
            return data
        }
        return try await session.receive()
    }

    public func close() async {
        await session.close()
    }

    private func encodeVLESSTarget(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        if let ipv4 = parseIPv4(target.host) {
            data.append(1) // ATYP IPv4
            data.append(contentsOf: ipv4)
        } else if let ipv6Data = parseIPv6ToData(target.host) {
            data.append(4) // ATYP IPv6
            data.append(ipv6Data)
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

    private func parseIPv6ToData(_ host: String) -> Data? {
        var sin6 = sockaddr_in6()
        return host.withCString { ptr -> Data? in
            guard inet_pton(AF_INET6, ptr, &sin6.sin6_addr) == 1 else { return nil }
            return withUnsafeBytes(of: sin6.sin6_addr) { Data($0) }
        }
    }

    // proto: message VLESSSession { string flow = 1; }
    // Field 1, wire type 2 (length-delimited): tag = 0x0A
    private func encodeVLESSAddons(flow: String?) -> Data {
        var data = Data()
        data.append(0x0A) // field 1, wire type 2
        let flowBytes = Data((flow ?? "").utf8)
        data.append(UInt8(flowBytes.count))
        data.append(flowBytes)
        return data
    }
}
