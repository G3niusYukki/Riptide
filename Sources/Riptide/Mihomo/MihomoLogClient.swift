import Foundation

// MARK: - Log Provider Protocol

/// Protocol for fetching log data from API
public protocol LogProvider: Sendable {
    func getLogs(level: String, lines: Int) async throws -> [String]
}

// MARK: - Mihomo Log Client

/// Client for fetching logs from mihomo API
public actor MihomoLogClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let parser = LogEntryParser()

    public init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    /// Constructs the log API URL with parameters
    public func logURL(level: String, lines: Int) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        components.path = "/logs"
        components.queryItems = [
            URLQueryItem(name: "level", value: level),
            URLQueryItem(name: "lines", value: String(lines))
        ]
        return components.url!
    }

    /// Fetches raw log lines from the API
    public func fetchLogs(level: String = "debug", lines: Int = 100) async throws -> [String] {
        let url = logURL(level: level, lines: lines)

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LogClientError.invalidResponse
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw LogClientError.decodingFailed
        }

        return string
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    /// Fetches and parses log entries
    public func fetchLogEntries(level: String = "debug", lines: Int = 100) async throws -> [LogEntry] {
        let lines = try await fetchLogs(level: level, lines: lines)
        return lines.map { parser.parse($0) }
    }
}

// MARK: - Log Client Errors

public enum LogClientError: Error, Equatable, Sendable {
    case invalidResponse
    case decodingFailed
    case networkError(String)
}
