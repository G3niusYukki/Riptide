import Foundation

public enum SingBoxPathsError: Error, Equatable, Sendable {
    case applicationSupportDirectoryNotFound
}

public struct SingBoxPaths: Sendable {
    public let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public var binaryPath: URL {
        baseDirectory.appendingPathComponent("Binaries/sing-box")
    }

    public var configPath: URL {
        baseDirectory.appendingPathComponent("config.json")
    }

    public var workingDirectory: URL {
        baseDirectory.appendingPathComponent("Data", isDirectory: true)
    }

    public init(fileManager: FileManager = .default) throws {
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SingBoxPathsError.applicationSupportDirectoryNotFound
        }

        self.baseDirectory = appSupport
            .appendingPathComponent("Riptide", isDirectory: true)
            .appendingPathComponent("singbox", isDirectory: true)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: binaryPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

public enum SingBoxAPIError: Error, Equatable, Sendable {
    case invalidBaseURL
    case networkError(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case decodingError(String)
}

public struct SingBoxVersion: Codable, Sendable {
    public let version: String
}

public struct SingBoxProxy: Codable, Sendable {
    public let name: String
    public let type: String
    public let udp: Bool
}

public struct SingBoxConnection: Codable, Sendable {
    public let id: String
    public let metadata: Metadata

    public struct Metadata: Codable, Sendable {
        public let network: String
        public let host: String
    }
}

public struct SingBoxTraffic: Codable, Sendable {
    public let up: Int
    public let down: Int
}

private struct SingBoxProxiesResponse: Codable {
    let proxies: [String: SingBoxProxy]
}

private struct SingBoxConnectionsResponse: Codable {
    let connections: [SingBoxConnection]
}

public actor SingBoxAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public init(session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:9090")!
        self.session = session
    }

    private func endpointURL(_ pathComponent: String) -> URL {
        baseURL.appendingPathComponent(pathComponent)
    }

    private func makeGETRequest(pathComponent: String) async throws -> Data {
        let request = URLRequest(url: endpointURL(pathComponent))

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            return data
        } catch let error as SingBoxAPIError {
            throw error
        } catch {
            throw SingBoxAPIError.networkError(String(describing: error))
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SingBoxAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = extractMessage(from: data)
                ?? String(data: data, encoding: .utf8)
                ?? "Request failed with status \(httpResponse.statusCode)"
            throw SingBoxAPIError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func extractMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object["message"] as? String ?? object["error"] as? String
    }

    public func getVersion() async throws -> SingBoxVersion {
        let data = try await makeGETRequest(pathComponent: "version")

        do {
            return try decoder.decode(SingBoxVersion.self, from: data)
        } catch {
            throw SingBoxAPIError.decodingError("Failed to decode version: \(String(describing: error))")
        }
    }

    public func getProxies() async throws -> [String: SingBoxProxy] {
        let data = try await makeGETRequest(pathComponent: "proxies")

        do {
            return try decoder.decode(SingBoxProxiesResponse.self, from: data).proxies
        } catch {
            throw SingBoxAPIError.decodingError("Failed to decode proxies: \(String(describing: error))")
        }
    }

    public func getConnections() async throws -> [SingBoxConnection] {
        let data = try await makeGETRequest(pathComponent: "connections")

        do {
            return try decoder.decode(SingBoxConnectionsResponse.self, from: data).connections
        } catch {
            throw SingBoxAPIError.decodingError("Failed to decode connections: \(String(describing: error))")
        }
    }

    public func getTraffic() async throws -> SingBoxTraffic {
        let data = try await makeGETRequest(pathComponent: "traffic")

        do {
            return try decoder.decode(SingBoxTraffic.self, from: data)
        } catch {
            throw SingBoxAPIError.decodingError("Failed to decode traffic: \(String(describing: error))")
        }
    }
}
