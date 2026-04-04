import Foundation

// MARK: - Error Types

/// Errors that can occur when communicating with the mihomo API
public enum MihomoAPIError: Error, Equatable, Sendable {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case apiError(statusCode: Int, message: String)
    case proxyNotFound(String)
}

// MARK: - Data Types

/// Information about a proxy node
public struct ProxyInfo: Codable, Sendable {
    public let name: String
    public let type: String
    public let alive: Bool?
    public let delay: Int?

    public init(name: String, type: String, alive: Bool? = nil, delay: Int? = nil) {
        self.name = name
        self.type = type
        self.alive = alive
        self.delay = delay
    }
}

/// Metadata for an active connection
public struct ConnectionMetadata: Codable, Sendable {
    public let network: String
    public let type: String
    public let sourceIP: String
    public let destinationIP: String?
    public let host: String?

    public init(network: String, type: String, sourceIP: String, destinationIP: String? = nil, host: String? = nil) {
        self.network = network
        self.type = type
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.host = host
    }

    enum CodingKeys: String, CodingKey {
        case network
        case type
        case sourceIP = "sourceIP"
        case destinationIP = "destinationIP"
        case host
    }
}

/// Information about an active connection
public struct ConnectionInfo: Codable, Sendable {
    public let id: String
    public let metadata: ConnectionMetadata
    public let upload: Int
    public let download: Int

    public init(id: String, metadata: ConnectionMetadata, upload: Int, download: Int) {
        self.id = id
        self.metadata = metadata
        self.upload = upload
        self.download = download
    }
}

// Intermediate response structures for parsing
private struct ProxiesResponse: Codable {
    let proxies: [String: ProxyInfo]
}

private struct ConnectionsResponse: Codable {
    let connections: [ConnectionInfo]
}

private struct DelayResponse: Codable {
    let delay: Int
}

private struct TrafficResponse: Codable {
    let up: Int
    let down: Int
}

// MARK: - API Client

/// Actor-based client for communicating with the mihomo REST API
public actor MihomoAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    /// Creates a new API client
    /// - Parameters:
    ///   - baseURL: The base URL of the mihomo API (e.g., http://127.0.0.1:9090)
    ///   - urlSession: The URLSession to use for requests (defaults to .shared)
    public init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
    }

    // MARK: - Private Helper

    /// Makes an HTTP request to the API
    /// - Parameters:
    ///   - url: The full URL for the request
    ///   - method: The HTTP method (GET, POST, PUT, DELETE, PATCH)
    ///   - body: Optional request body data
    /// - Returns: Tuple of response data and URLResponse
    /// - Throws: MihomoAPIError on failure
    private func makeRequest(url: URL, method: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        // Set default headers for JSON
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            return (data, response)
        } catch {
            throw MihomoAPIError.networkError(String(describing: error))
        }
    }

    /// Validates the HTTP response and converts error status codes to MihomoAPIError
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MihomoAPIError.networkError("Invalid response type")
        }

        let statusCode = httpResponse.statusCode

        // Success status codes: 200-299
        guard (200...299).contains(statusCode) else {
            // Try to extract error message from response body
            let message = extractMessage(from: data) ?? "Request failed with status \(statusCode)"

            if statusCode == 404 {
                // Try to extract proxy name from message for proxyNotFound error
                let proxyPattern = "Proxy '([^']+)'"
                if let regex = try? NSRegularExpression(pattern: proxyPattern, options: []),
                   let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.utf16.count)) {
                    let proxyName = (message as NSString).substring(with: match.range(at: 1))
                    throw MihomoAPIError.proxyNotFound(proxyName)
                }
            }

            throw MihomoAPIError.apiError(statusCode: statusCode, message: message)
        }
    }

    /// Extracts a message from JSON response data
    private func extractMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["message"] as? String ?? json["error"] as? String
    }

    // MARK: - API Methods

    /// Checks if the mihomo API is healthy
    /// - Returns: true if the API responds with 200 status
    public func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("version")

        do {
            let (_, response) = try await makeRequest(url: url, method: "GET")
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            // Log error for diagnostics without throwing
            print("[MihomoAPIClient] Health check failed: \(String(describing: error))")
            return false
        }
    }

    /// Gets all available proxies
    /// - Returns: Array of ProxyInfo objects
    public func getProxies() async throws -> [ProxyInfo] {
        let url = baseURL.appendingPathComponent("proxies")

        let (data, response) = try await makeRequest(url: url, method: "GET")
        try validateResponse(response, data: data)

        do {
            let response = try decoder.decode(ProxiesResponse.self, from: data)
            return Array(response.proxies.values)
        } catch {
            throw MihomoAPIError.decodingError("Failed to decode proxies: \(String(describing: error))")
        }
    }

    /// Switches the active proxy in a proxy group
    /// - Parameters:
    ///   - proxyName: The name of the proxy to switch to
    ///   - group: The name of the proxy group (defaults to "GLOBAL")
    public func switchProxy(to proxyName: String, inGroup group: String = "GLOBAL") async throws {
        let url = baseURL.appendingPathComponent("proxies").appendingPathComponent(group)

        let bodyDict: [String: String] = ["name": proxyName]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw MihomoAPIError.networkError("Failed to encode request body")
        }

        let (data, response) = try await makeRequest(url: url, method: "PUT", body: body)
        try validateResponse(response, data: data)
    }

    /// Tests the delay/latency of a proxy
    /// - Parameters:
    ///   - name: The name of the proxy to test
    ///   - url: The test URL to use (typically https://www.google.com)
    ///   - timeout: Timeout in milliseconds
    /// - Returns: The measured delay in milliseconds
    public func testProxyDelay(name: String, url: String, timeout: Int) async throws -> Int {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path = "/proxies/\(name)/delay"
        components?.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout))
        ]

        guard let requestURL = components?.url else {
            throw MihomoAPIError.invalidURL
        }

        let (data, response) = try await makeRequest(url: requestURL, method: "GET")
        try validateResponse(response, data: data)

        do {
            let delayResponse = try decoder.decode(DelayResponse.self, from: data)
            return delayResponse.delay
        } catch {
            throw MihomoAPIError.decodingError("Failed to decode delay response: \(String(describing: error))")
        }
    }

    /// Gets all active connections
    /// - Returns: Array of ConnectionInfo objects
    public func getConnections() async throws -> [ConnectionInfo] {
        let url = baseURL.appendingPathComponent("connections")

        let (data, response) = try await makeRequest(url: url, method: "GET")
        try validateResponse(response, data: data)

        do {
            let response = try decoder.decode(ConnectionsResponse.self, from: data)
            return response.connections
        } catch {
            throw MihomoAPIError.decodingError("Failed to decode connections: \(String(describing: error))")
        }
    }

    /// Closes a specific connection by ID
    /// - Parameter id: The connection ID to close
    public func closeConnection(id: String) async throws {
        let url = baseURL.appendingPathComponent("connections").appendingPathComponent(id)

        let (data, response) = try await makeRequest(url: url, method: "DELETE")
        try validateResponse(response, data: data)
    }

    /// Closes all active connections
    public func closeAllConnections() async throws {
        let url = baseURL.appendingPathComponent("connections")

        let (data, response) = try await makeRequest(url: url, method: "DELETE")
        try validateResponse(response, data: data)
    }

    /// Gets current traffic statistics
    /// - Returns: Tuple of (upload, download) in bytes
    public func getTraffic() async throws -> (up: Int, down: Int) {
        let url = baseURL.appendingPathComponent("traffic")

        let (data, response) = try await makeRequest(url: url, method: "GET")
        try validateResponse(response, data: data)

        do {
            let traffic = try decoder.decode(TrafficResponse.self, from: data)
            return (up: traffic.up, down: traffic.down)
        } catch {
            throw MihomoAPIError.decodingError("Failed to decode traffic: \(String(describing: error))")
        }
    }

    /// Gets recent log entries
    /// - Parameters:
    ///   - level: Log level filter (info, warning, error, debug, silent)
    ///   - lines: Number of log lines to retrieve
    /// - Returns: Array of log strings
    public func getLogs(level: String, lines: Int) async throws -> [String] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path = "/logs"
        components?.queryItems = [
            URLQueryItem(name: "level", value: level),
            URLQueryItem(name: "lines", value: String(lines))
        ]

        guard let url = components?.url else {
            throw MihomoAPIError.invalidURL
        }

        let (data, response) = try await makeRequest(url: url, method: "GET")
        try validateResponse(response, data: data)

        // Logs response is a stream of JSON lines, parse as array of strings
        guard let string = String(data: data, encoding: .utf8) else {
            throw MihomoAPIError.decodingError("Failed to decode logs as UTF-8")
        }

        // Split by newlines and filter empty lines
        return string.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    /// Reloads the configuration from disk
    public func reloadConfig() async throws {
        let url = baseURL.appendingPathComponent("configs")

        let (data, response) = try await makeRequest(url: url, method: "PUT")
        try validateResponse(response, data: data)
    }

    /// Applies a partial configuration update
    /// - Parameter partial: Dictionary of configuration values to update
    public func patchConfig(partial: [String: Any]) async throws {
        let url = baseURL.appendingPathComponent("configs")

        guard let body = try? JSONSerialization.data(withJSONObject: partial) else {
            throw MihomoAPIError.networkError("Failed to encode request body")
        }

        let (data, response) = try await makeRequest(url: url, method: "PATCH", body: body)
        try validateResponse(response, data: data)
    }
}
