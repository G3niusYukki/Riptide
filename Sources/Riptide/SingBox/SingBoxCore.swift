import Foundation

public struct SingBoxPaths: Sendable {
    public let baseDirectory: URL
    
    public var binaryPath: URL {
        baseDirectory.appendingPathComponent("Binaries/sing-box")
    }
    
    public var configPath: URL {
        baseDirectory.appendingPathComponent("config.json")
    }
    
    public var workingDirectory: URL {
        baseDirectory.appendingPathComponent("Data", isDirectory: true)
    }
    
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseDirectory = appSupport
            .appendingPathComponent("Riptide", isDirectory: true)
            .appendingPathComponent("singbox", isDirectory: true)
    }
    
    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
    }
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

public actor SingBoxAPIClient {
    private let baseURL: URL
    private let session: URLSession
    
    public init(baseURL: URL = URL(string: "http://127.0.0.1:9090")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }
    
    public func getVersion() async throws -> SingBoxVersion {
        var request = URLRequest(url: baseURL.appendingPathComponent("/version"))
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(SingBoxVersion.self, from: data)
    }
    
    public func getProxies() async throws -> [String: SingBoxProxy] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/proxies"))
        let (data, _) = try await session.data(for: request)
        struct Response: Codable { let proxies: [String: SingBoxProxy] }
        return try JSONDecoder().decode(Response.self, from: data).proxies
    }
    
    public func getConnections() async throws -> [SingBoxConnection] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/connections"))
        let (data, _) = try await session.data(for: request)
        struct Response: Codable { let connections: [SingBoxConnection] }
        return try JSONDecoder().decode(Response.self, from: data).connections
    }
    
    public func getTraffic() async throws -> SingBoxTraffic {
        var request = URLRequest(url: baseURL.appendingPathComponent("/traffic"))
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(SingBoxTraffic.self, from: data)
    }
}
