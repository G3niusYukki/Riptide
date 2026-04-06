import Foundation
import Testing
@testable import Riptide

@Suite("SingBox API Client", .serialized)
struct SingBoxAPIClientTests {
    private func setupMock() {
        MockURLProtocol.reset()
    }

    @Test("getVersion requests /version and decodes response")
    func testGetVersion() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
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
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
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
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
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
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
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
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
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
