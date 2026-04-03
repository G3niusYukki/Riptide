import Foundation
import CryptoKit
import CommonCrypto

public enum TrojanError: Error, Equatable, Sendable {
    case invalidPassword
    case malformedResponse
    case tlsRequired
}

public actor TrojanStream: Sendable {
    private let session: any TransportSession
    private let passwordHash: String
    private var recvBuffer = Data()

    public init(session: any TransportSession, password: String) throws {
        self.session = session
        // Trojan protocol requires SHA-224 hash of the password (28 bytes / 56 hex chars)
        let passwordData = Data(password.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
        passwordData.withUnsafeBytes { ptr in
            _ = CC_SHA224(ptr.baseAddress, CC_LONG(passwordData.count), &hash)
        }
        self.passwordHash = hash.map { String(format: "%02x", $0) }.joined()
    }

    public func connect(to target: ConnectionTarget) async throws {
        // Trojan header: hex(password) + CRLF + target address + CRLF
        var header = Data()
        header.append(contentsOf: passwordHash.utf8)
        header.append(contentsOf: "\r\n".utf8)
        header.append(try encodeTrojanTarget(target))
        header.append(contentsOf: "\r\n".utf8)

        try await session.send(header)
    }

    // MARK: - Framing

    public func send(_ data: Data) async throws {
        // Trojan payload framing: hex-length CRLF + data + CRLF
        let hexLen = String(data.count, radix: 16, uppercase: false)
        try await session.send(Data("\(hexLen)\r\n".utf8))
        try await session.send(data)
        try await session.send(Data("\r\n".utf8))
    }

    public func receive() async throws -> Data {
        // 1. Read hex-length + CRLF by draining the buffer.
        // If the buffer doesn't contain a full line yet, fetch more data.
        while true {
            if let crlfIndex = recvBuffer.range(of: Data([0x0D, 0x0A])) {
                // Found CRLF — extract the hex length
                let lenData = recvBuffer[..<crlfIndex.lowerBound]
                recvBuffer.removeSubrange(...crlfIndex.upperBound)
                guard let count = Int(String(data: lenData, encoding: .utf8) ?? "", radix: 16) else {
                    throw TrojanError.malformedResponse
                }

                // 2. Read `count` bytes from the buffer, fetching more if needed.
                while recvBuffer.count < count {
                    let more = try await session.receive()
                    recvBuffer.append(more)
                }
                let body = recvBuffer.prefix(count)
                recvBuffer.removeFirst(count)

                // 3. Read and discard trailing CRLF
                while recvBuffer.count < 2 {
                    let more = try await session.receive()
                    recvBuffer.append(more)
                }
                recvBuffer.removeFirst(2)

                return Data(body)
            } else {
                // Buffer doesn't contain CRLF yet — fetch more data.
                let more = try await session.receive()
                recvBuffer.append(more)
            }
        }
    }

    public func close() async {
        await session.close()
    }

    // MARK: - Address encoding

    private func encodeTrojanTarget(_ target: ConnectionTarget) throws -> Data {
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

    private func parseIPv6ToData(_ addr: String) -> Data? {
        var sin6 = sockaddr_in6()
        return addr.withCString { ptr -> Data? in
            guard inet_pton(AF_INET6, ptr, &sin6.sin6_addr) == 1 else { return nil }
            return withUnsafeBytes(of: sin6.sin6_addr) { Data($0) }
        }
    }
}
