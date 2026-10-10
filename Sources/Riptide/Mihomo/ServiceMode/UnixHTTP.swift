import Foundation

/// A parsed HTTP/1.1 request received over a Unix domain socket.
///
/// Header keys are lowercased on parse so lookups are case-insensitive.
public struct UnixHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        self.body = body
    }

    /// Decodes the body as UTF-8 JSON.
    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    // MARK: - I/O

    /// Reads one full request (headers + Content-Length body) from `fd`.
    /// Returns nil on malformed input or read failure.
    static func read(from fd: Int32) -> Self? {
        guard let header = UnixHTTP.readHeaderBlock(fd: fd) else { return nil }
        guard var request = Self.parse(headerText: header.text) else { return nil }
        if let contentLength = Int(request.headers["content-length"] ?? ""), contentLength > 0 {
            guard contentLength <= UnixHTTP.maxBodyBytes else { return nil }
            var body = header.leftover
            guard body.count <= contentLength else { return nil }
            if body.count < contentLength {
                guard let rest = UnixHTTP.readCount(fd: fd, count: contentLength - body.count) else {
                    return nil
                }
                body.append(rest)
            }
            request = UnixHTTPRequest(
                method: request.method,
                path: request.path,
                headers: request.headers,
                body: body
            )
        }
        return request
    }

    /// Parses header block text (everything before `\r\n\r\n`).
    static func parse(headerText: String) -> Self? {
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        guard ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(method) else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return UnixHTTPRequest(method: method, path: path, headers: headers, body: Data())
    }

    /// Serializes the request for the wire. Adds Content-Length when a body
    /// is present.
    func serialized() -> Data {
        var text = "\(method) \(path) HTTP/1.1\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            text += "\(name): \(value)\r\n"
        }
        if !body.isEmpty {
            text += "content-length: \(body.count)\r\n"
        }
        text += "connection: close\r\n\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }
}

/// An HTTP/1.1 response sent back over a Unix domain socket.
public struct UnixHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let reason: String
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, reason: String? = nil, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.reason = reason ?? Self.defaultReason(for: status)
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        self.body = body
    }

    /// Builds a JSON response from an `Encodable` value.
    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> Self {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return UnixHTTPResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: data
        )
    }

    /// Builds a JSON error response.
    public static func error(_ message: String, status: Int) -> Self {
        json(MihomoServiceProtocol.ErrorResponse(error: message), status: status)
    }

    private static func defaultReason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        default: return "Status \(status)"
        }
    }

    /// Decodes the body as UTF-8 JSON.
    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    func serialized() -> Data {
        var text = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            text += "\(name): \(value)\r\n"
        }
        text += "content-length: \(body.count)\r\n"
        text += "connection: close\r\n\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }

    /// Reads one full response (status line + headers + body) from `fd`.
    /// The body is framed by Content-Length when present, otherwise read to
    /// EOF (the server always closes the connection).
    static func read(from fd: Int32) -> Self? {
        guard let header = UnixHTTP.readHeaderBlock(fd: fd) else { return nil }
        let lines = header.text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }
        let parts = statusLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let status = Int(parts[1]) else { return nil }
        let reason = parts.count >= 3 ? parts[2...].joined(separator: " ") : ""
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        var body = header.leftover
        if let contentLength = Int(headers["content-length"] ?? ""), contentLength > 0 {
            guard contentLength <= UnixHTTP.maxBodyBytes else { return nil }
            guard body.count <= contentLength else { return nil }
            if body.count < contentLength {
                guard let rest = UnixHTTP.readCount(fd: fd, count: contentLength - body.count) else {
                    return nil
                }
                body.append(rest)
            }
        } else if body.isEmpty, headers["transfer-encoding"] == nil {
            // No framing header: read until EOF.
            while let chunk = UnixHTTP.recvChunk(fd: fd, max: 65536), !chunk.isEmpty {
                if body.count + chunk.count > UnixHTTP.maxBodyBytes { return nil }
                body.append(chunk)
            }
        }
        return UnixHTTPResponse(status: status, reason: reason, headers: headers, body: body)
    }
}

/// Shared low-level socket read helpers and protocol limits. All reads are
/// per-call local: framing state never escapes a single connection.
enum UnixHTTP {
    /// Cap on request/response bodies (configs are a few hundred KB; cores
    /// are never transferred over this socket, only file paths).
    static let maxBodyBytes = 8 * 1024 * 1024
    /// Cap on the header block.
    static let maxHeaderBytes = 64 * 1024

    /// The header block read from one connection: its UTF-8 text plus any
    /// bytes that already arrived past the `\r\n\r\n` terminator.
    struct HeaderBlock {
        let text: String
        let leftover: Data
    }

    /// Reads until the `\r\n\r\n` header terminator.
    static func readHeaderBlock(fd: Int32) -> HeaderBlock? {
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.count < maxHeaderBytes {
            guard let chunk = recvChunk(fd: fd, max: 4096) else { return nil }
            if chunk.isEmpty { return nil } // EOF before terminator
            buffer.append(chunk)
            if let range = buffer.range(of: terminator) {
                let headerData = Data(buffer[buffer.startIndex..<range.lowerBound])
                let leftover = Data(buffer[range.upperBound...])
                guard let text = String(data: headerData, encoding: .utf8) else { return nil }
                return HeaderBlock(text: text, leftover: leftover)
            }
        }
        return nil
    }

    /// Reads exactly `count` bytes.
    static func readCount(fd: Int32, count: Int) -> Data? {
        var result = Data()
        while result.count < count {
            guard let chunk = recvChunk(fd: fd, max: count - result.count), !chunk.isEmpty else { return nil }
            result.append(chunk)
        }
        return result
    }

    /// Receives up to `max` bytes. Empty Data means EOF. Nil means error.
    static func recvChunk(fd: Int32, max: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: max)
        let received = recv(fd, &buffer, max, 0)
        if received < 0 { return nil }
        if received == 0 { return Data() }
        return Data(buffer[..<received])
    }

    /// Sends the full contents of `data`. Returns false on failure.
    static func sendAll(fd: Int32, data: Data) -> Bool {
        var sent = 0
        let total = data.count
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return total == 0 }
            while sent < total {
                let written = send(fd, base + sent, total - sent, 0)
                if written <= 0 { return false }
                sent += written
            }
            return true
        }
    }
}
