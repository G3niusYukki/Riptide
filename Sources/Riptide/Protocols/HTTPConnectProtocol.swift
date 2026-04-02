import Foundation

public struct HTTPConnectProtocol: OutboundProxyProtocol {
    public init() {}

    public func makeConnectRequest(for target: ConnectionTarget) throws -> [Data] {
        guard (1...65_535).contains(target.port) else {
            throw ProtocolError.invalidTarget("port out of range")
        }
        let host = target.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ProtocolError.invalidTarget("host is empty")
        }

        let endpoint = "\(host):\(target.port)"
        let request = "CONNECT \(endpoint) HTTP/1.1\r\nHost: \(endpoint)\r\n\r\n"
        return [Data(request.utf8)]
    }

    public func parseConnectResponse(_ data: Data) throws -> ConnectResponse {
        guard let response = String(data: data, encoding: .utf8) else {
            throw ProtocolError.malformedResponse("non-utf8 http response")
        }
        guard let statusLine = response.split(separator: "\r\n", omittingEmptySubsequences: false).first else {
            throw ProtocolError.malformedResponse("missing status line")
        }

        let parts = statusLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw ProtocolError.malformedResponse("invalid status line")
        }

        if (200...299).contains(status) {
            return .success
        }
        throw ProtocolError.connectionRejected("HTTP status \(status)")
    }
}
