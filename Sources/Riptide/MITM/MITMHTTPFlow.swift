import Foundation

public struct MITMHTTPHeader: Equatable, Sendable, Identifiable {
    public var id: String { "\(name):\(value)" }
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MITMHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let version: String
    public let headers: [MITMHTTPHeader]
    public let bodySize: Int
    public let bodyPreview: Data

    public init(
        method: String,
        path: String,
        version: String,
        headers: [MITMHTTPHeader],
        bodySize: Int,
        bodyPreview: Data
    ) {
        self.method = method
        self.path = path
        self.version = version
        self.headers = headers
        self.bodySize = bodySize
        self.bodyPreview = bodyPreview
    }

    public func headerValue(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var bodyPreviewText: String {
        String(data: bodyPreview, encoding: .utf8) ?? bodyPreview.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MITMHTTPResponse: Equatable, Sendable {
    public let version: String
    public let statusCode: Int
    public let reasonPhrase: String
    public let headers: [MITMHTTPHeader]
    public let bodySize: Int
    public let bodyPreview: Data

    public init(
        version: String,
        statusCode: Int,
        reasonPhrase: String,
        headers: [MITMHTTPHeader],
        bodySize: Int,
        bodyPreview: Data
    ) {
        self.version = version
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
        self.bodySize = bodySize
        self.bodyPreview = bodyPreview
    }

    public func headerValue(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var bodyPreviewText: String {
        String(data: bodyPreview, encoding: .utf8) ?? bodyPreview.map { String(format: "%02x", $0) }.joined()
    }
}

public enum MITMHTTPMessage: Equatable, Sendable {
    case request(MITMHTTPRequest)
    case response(MITMHTTPResponse)
}

public enum MITMHTTPMessageDirection: Sendable {
    case request
    case response
}

public struct MITMHTTPFlowRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let host: String
    public let port: Int
    public let startedAt: Date
    public let updatedAt: Date
    public let request: MITMHTTPRequest
    public let response: MITMHTTPResponse?

    public init(
        id: UUID = UUID(),
        host: String,
        port: Int,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        request: MITMHTTPRequest,
        response: MITMHTTPResponse? = nil
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.request = request
        self.response = response
    }

    public func attaching(response: MITMHTTPResponse, at date: Date = Date()) -> MITMHTTPFlowRecord {
        MITMHTTPFlowRecord(
            id: id,
            host: host,
            port: port,
            startedAt: startedAt,
            updatedAt: date,
            request: request,
            response: response
        )
    }
}

public struct MITMHTTPMessageParser: Sendable {
    private let direction: MITMHTTPMessageDirection
    private let bodyPreviewLimit: Int
    private var buffer = Data()

    public init(direction: MITMHTTPMessageDirection, bodyPreviewLimit: Int = 16 * 1024) {
        self.direction = direction
        self.bodyPreviewLimit = bodyPreviewLimit
    }

    public mutating func append(_ data: Data) -> [MITMHTTPMessage] {
        guard data.isEmpty == false else { return [] }
        buffer.append(data)

        var messages: [MITMHTTPMessage] = []
        while let message = parseNextMessage() {
            messages.append(message)
        }
        return messages
    }

    private mutating func parseNextMessage() -> MITMHTTPMessage? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            buffer.removeAll()
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let startLine = lines.first, startLine.isEmpty == false else {
            buffer.removeSubrange(buffer.startIndex..<headerRange.upperBound)
            return nil
        }

        let headers = parseHeaders(lines.dropFirst())
        let contentLength = contentLength(from: headers)
        let bodyStart = headerRange.upperBound
        let messageEnd = bodyStart + contentLength
        guard buffer.count >= messageEnd else {
            return nil
        }

        let body = Data(buffer[bodyStart..<messageEnd])
        let preview = Data(body.prefix(max(0, bodyPreviewLimit)))
        buffer.removeSubrange(buffer.startIndex..<messageEnd)

        switch direction {
        case .request:
            return parseRequest(startLine: startLine, headers: headers, bodySize: contentLength, bodyPreview: preview)
        case .response:
            return parseResponse(startLine: startLine, headers: headers, bodySize: contentLength, bodyPreview: preview)
        }
    }

    private func parseRequest(
        startLine: String,
        headers: [MITMHTTPHeader],
        bodySize: Int,
        bodyPreview: Data
    ) -> MITMHTTPMessage? {
        let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }
        return .request(
            MITMHTTPRequest(
                method: String(parts[0]),
                path: String(parts[1]),
                version: String(parts[2]),
                headers: headers,
                bodySize: bodySize,
                bodyPreview: bodyPreview
            )
        )
    }

    private func parseResponse(
        startLine: String,
        headers: [MITMHTTPHeader],
        bodySize: Int,
        bodyPreview: Data
    ) -> MITMHTTPMessage? {
        let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, let statusCode = Int(parts[1]) else { return nil }
        let reasonPhrase = parts.count >= 3 ? String(parts[2]) : ""
        return .response(
            MITMHTTPResponse(
                version: String(parts[0]),
                statusCode: statusCode,
                reasonPhrase: reasonPhrase,
                headers: headers,
                bodySize: bodySize,
                bodyPreview: bodyPreview
            )
        )
    }

    private func parseHeaders(_ lines: ArraySlice<String>) -> [MITMHTTPHeader] {
        lines.compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { return nil }
            return MITMHTTPHeader(name: name, value: value)
        }
    }

    private func contentLength(from headers: [MITMHTTPHeader]) -> Int {
        guard
            let value = headers.first(where: { $0.name.caseInsensitiveCompare("content-length") == .orderedSame })?.value,
            let length = Int(value),
            length > 0
        else {
            return 0
        }
        return length
    }
}

public actor MITMHTTPFlowObserver {
    private let manager: MITMManager
    private let host: String
    private let port: Int
    private var requestParser: MITMHTTPMessageParser
    private var responseParser: MITMHTTPMessageParser
    private var pendingFlowIDs: [UUID] = []

    public init(manager: MITMManager, host: String, port: Int) {
        self.manager = manager
        self.host = host
        self.port = port
        self.requestParser = MITMHTTPMessageParser(direction: .request)
        self.responseParser = MITMHTTPMessageParser(direction: .response)
    }

    public func observeClientToUpstream(_ data: Data) async {
        let messages = requestParser.append(data)
        for message in messages {
            guard case .request(let request) = message else { continue }
            let id = await manager.recordHTTPRequest(host: host, port: port, request: request)
            pendingFlowIDs.append(id)
        }
    }

    public func observeUpstreamToClient(_ data: Data) async {
        let messages = responseParser.append(data)
        for message in messages {
            guard case .response(let response) = message else { continue }
            guard pendingFlowIDs.isEmpty == false else { continue }
            let id = pendingFlowIDs.removeFirst()
            await manager.recordHTTPResponse(flowID: id, response: response)
        }
    }
}
