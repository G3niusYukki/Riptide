import Foundation
import Testing
@testable import Riptide

// MARK: - SingBox Mock URL Protocol (isolated from Mihomo tests)

final class SingBoxMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var errorHandler: (@Sendable (URLRequest) -> Error?)?
    
    static func reset() {
        requestHandler = nil
        errorHandler = nil
    }
    
    static func setRequestHandler(_ handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        requestHandler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let currentRequest = self.request
        let client = self.client

        if let error = Self.errorHandler?(currentRequest) {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(currentRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func makeSingBoxMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SingBoxMockURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}

@Suite("SingBox API Client", .serialized)
struct SingBoxAPIClientTests {
    private func setupMock() {
        SingBoxMockURLProtocol.reset()
    }

    @Test("getVersion requests /version and decodes response")
    func testGetVersion() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeSingBoxMockSession()

        SingBoxMockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/version")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"version\":\"1.13.0\"}".utf8))
        }

        let client = SingBoxAPIClient(baseURL: baseURL, session: mockSession)
        let version = try await client.getVersion()

        #expect(version.version == "1.13.0")
    }

    @Test("getProxies requests /proxies and decodes proxy map")
    func testGetProxies() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeSingBoxMockSession()

        SingBoxMockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/proxies")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "proxies": {
                "ProxyA": { "name": "ProxyA", "type": "vless", "udp": true }
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = SingBoxAPIClient(baseURL: baseURL, session: mockSession)
        let proxies = try await client.getProxies()

        #expect(proxies["ProxyA"]?.name == "ProxyA")
        #expect(proxies["ProxyA"]?.type == "vless")
        #expect(proxies["ProxyA"]?.udp == true)
    }

    @Test("getConnections requests /connections and decodes array")
    func testGetConnections() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeSingBoxMockSession()

        SingBoxMockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/connections")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "connections": [
                {
                  "id": "conn-1",
                  "metadata": { "network": "tcp", "host": "example.com" }
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }

        let client = SingBoxAPIClient(baseURL: baseURL, session: mockSession)
        let connections = try await client.getConnections()

        #expect(connections.count == 1)
        #expect(connections[0].id == "conn-1")
        #expect(connections[0].metadata.network == "tcp")
        #expect(connections[0].metadata.host == "example.com")
    }

    @Test("getTraffic requests /traffic and decodes values")
    func testGetTraffic() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeSingBoxMockSession()

        SingBoxMockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/traffic")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"up\":123,\"down\":456}".utf8))
        }

        let client = SingBoxAPIClient(baseURL: baseURL, session: mockSession)
        let traffic = try await client.getTraffic()

        #expect(traffic.up == 123)
        #expect(traffic.down == 456)
    }

    @Test("non-2xx responses surface API error")
    func testNon2xxResponse() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeSingBoxMockSession()

        SingBoxMockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"message\":\"controller unavailable\"}".utf8))
        }

        let client = SingBoxAPIClient(baseURL: baseURL, session: mockSession)

        await #expect(throws: SingBoxAPIError.apiError(statusCode: 503, message: "controller unavailable")) {
            _ = try await client.getVersion()
        }
    }
}

@Suite("SingBox Paths")
struct SingBoxPathsTests {
    @Test("paths resolve under Application Support")
    func testPathsLayout() throws {
        let paths = try SingBoxPaths()

        #expect(paths.baseDirectory.path.contains("Application Support/Riptide/singbox"))
        #expect(paths.binaryPath.path.hasSuffix("Riptide/singbox/Binaries/sing-box"))
        #expect(paths.configPath.lastPathComponent == "config.json")
        #expect(paths.workingDirectory.lastPathComponent == "Data")
    }

    @Test("ensureDirectories creates binary and working directories")
    func testEnsureDirectoriesCreatesExpectedFolders() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let baseDirectory = tempRoot.appendingPathComponent("Application Support/Riptide/singbox", isDirectory: true)
        let paths = SingBoxPaths(baseDirectory: baseDirectory)

        try paths.ensureDirectories()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: paths.workingDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(FileManager.default.fileExists(atPath: paths.binaryPath.deletingLastPathComponent().path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        try? FileManager.default.removeItem(at: tempRoot)
    }
}
