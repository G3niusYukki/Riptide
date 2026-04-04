import Foundation
import Testing
@testable import Riptide

// MARK: - Mock URL Protocol

/// Thread-safe storage for MockURLProtocol using NSLock
final class MockURLProtocolStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private var _errorHandler: (@Sendable (URLRequest) -> Error?)?

    var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            _requestHandler = newValue
            lock.unlock()
        }
    }

    var errorHandler: (@Sendable (URLRequest) -> Error?)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _errorHandler
        }
        set {
            lock.lock()
            _errorHandler = newValue
            lock.unlock()
        }
    }

    func reset() {
        lock.lock()
        _requestHandler = nil
        _errorHandler = nil
        lock.unlock()
    }
}

/// Mock URLProtocol for testing HTTP requests without making real network calls
final class MockURLProtocol: URLProtocol {
    static let storage = MockURLProtocolStorage()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Execute synchronously to avoid race conditions
        let currentRequest = self.request
        let client = self.client

        if let error = MockURLProtocol.storage.errorHandler?(currentRequest) {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let handler = MockURLProtocol.storage.requestHandler else {
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

// MARK: - Test Helpers

extension MockURLProtocol {
    static func reset() {
        storage.reset()
    }

    static func setRequestHandler(_ handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        storage.requestHandler = handler
    }

    static func setErrorHandler(_ handler: (@Sendable (URLRequest) -> Error?)?) {
        storage.errorHandler = handler
    }
}

extension URLSession {
    static func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        // Disable caching and connection pooling
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}

// MARK: - MihomoAPIClient Tests

@Suite("Mihomo API Client", .serialized)
struct MihomoAPIClientTests {

    // Helper to set up mock before each test
    private func setupMock() {
        MockURLProtocol.reset()
    }

    // MARK: - Test 1: Health Check Success

    @Test("healthCheck returns true on 200 response")
    func testHealthCheckSuccess() async {
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
            let data = "{\"version\": \"v1.0.0\"}".data(using: .utf8)!
            return (response, data)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        let result = await client.healthCheck()

        #expect(result == true)
    }

    // MARK: - Test 2: Health Check Failure

    @Test("healthCheck returns false on connection error")
    func testHealthCheckFailure() async {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setErrorHandler { _ in
            return URLError(.cannotConnectToHost)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        let result = await client.healthCheck()

        #expect(result == false)
    }

    // MARK: - Test 3: Get Proxies

    @Test("getProxies returns parsed proxy array")
    func testGetProxies() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        let jsonResponse = """
        {
            "proxies": {
                "Proxy1": {
                    "name": "Proxy1",
                    "type": "Shadowsocks",
                    "alive": true,
                    "delay": 150
                },
                "Proxy2": {
                    "name": "Proxy2",
                    "type": "VMess",
                    "alive": false,
                    "delay": 0
                }
            }
        }
        """

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/proxies")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        let proxies = try await client.getProxies()

        #expect(proxies.count == 2)
        // Sort by name for consistent ordering since dictionary order isn't guaranteed
        let sortedProxies = proxies.sorted { $0.name < $1.name }
        #expect(sortedProxies[0].name == "Proxy1")
        #expect(sortedProxies[0].type == "Shadowsocks")
        #expect(sortedProxies[0].alive == true)
        #expect(sortedProxies[0].delay == 150)
        #expect(sortedProxies[1].name == "Proxy2")
        #expect(sortedProxies[1].type == "VMess")
        #expect(sortedProxies[1].alive == false)
    }

    // MARK: - Test 4: Switch Proxy

    @Test("switchProxy sends correct PUT request")
    func testSwitchProxy() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/proxies/GLOBAL")
            #expect(request.httpMethod == "PUT")

            // Read body data - either from httpBody or httpBodyStream
            var bodyData: Data?
            if let body = request.httpBody {
                bodyData = body
            } else if let stream = request.httpBodyStream {
                let tempData = NSMutableData()
                stream.open()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 1024)
                    if read > 0 {
                        tempData.append(buffer, length: read)
                    }
                }
                stream.close()
                bodyData = tempData as Data
            }

            let bodyString = bodyData.flatMap { String(data: $0, encoding: .utf8) }
            #expect(bodyString?.contains("Proxy1") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        try await client.switchProxy(to: "Proxy1", inGroup: "GLOBAL")

        // Test passes if no error thrown
    }

    // MARK: - Test 5: API Error

    @Test("throws apiError on 404 response")
    func testAPIError() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "{\"message\": \"Proxy not found\"}".data(using: .utf8)!
            return (response, data)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)

        await #expect(throws: MihomoAPIError.self) {
            _ = try await client.getProxies()
        }
    }

    // MARK: - Additional Tests

    @Test("testProxyDelay returns delay value")
    func testTestProxyDelay() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        let jsonResponse = """
        {
            "delay": 200
        }
        """

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/proxies/Proxy1/delay")
            #expect(request.httpMethod == "GET")
            #expect(request.url?.query?.contains("url=https://www.google.com") == true)
            #expect(request.url?.query?.contains("timeout=5000") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        let delay = try await client.testProxyDelay(name: "Proxy1", url: "https://www.google.com", timeout: 5000)

        #expect(delay == 200)
    }

    @Test("getConnections returns parsed connection array")
    func testGetConnections() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        let jsonResponse = """
        {
            "connections": [
                {
                    "id": "conn-1",
                    "metadata": {
                        "network": "tcp",
                        "type": "HTTP",
                        "sourceIP": "127.0.0.1",
                        "destinationIP": "1.2.3.4",
                        "host": "example.com"
                    },
                    "upload": 1024,
                    "download": 2048
                }
            ]
        }
        """

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/connections")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        let connections = try await client.getConnections()

        #expect(connections.count == 1)
        #expect(connections[0].id == "conn-1")
        #expect(connections[0].metadata.network == "tcp")
        #expect(connections[0].metadata.host == "example.com")
        #expect(connections[0].upload == 1024)
        #expect(connections[0].download == 2048)
    }

    @Test("closeConnection sends DELETE request")
    func testCloseConnection() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/connections/conn-123")
            #expect(request.httpMethod == "DELETE")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        try await client.closeConnection(id: "conn-123")

        // Test passes if no error thrown
    }

    @Test("closeAllConnections sends DELETE to /connections")
    func testCloseAllConnections() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/connections")
            #expect(request.httpMethod == "DELETE")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        try await client.closeAllConnections()

        // Test passes if no error thrown
    }

    @Test("reloadConfig sends PUT request")
    func testReloadConfig() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/configs")
            #expect(request.httpMethod == "PUT")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        try await client.reloadConfig()

        // Test passes if no error thrown
    }

    @Test("patchConfig sends PATCH with correct body")
    func testPatchConfig() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            #expect(request.url?.path == "/configs")
            #expect(request.httpMethod == "PATCH")

            // Read body data - either from httpBody or httpBodyStream
            var bodyData: Data?
            if let body = request.httpBody {
                bodyData = body
            } else if let stream = request.httpBodyStream {
                let tempData = NSMutableData()
                stream.open()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 1024)
                    if read > 0 {
                        tempData.append(buffer, length: read)
                    }
                }
                stream.close()
                bodyData = tempData as Data
            }

            let bodyString = bodyData.flatMap { String(data: $0, encoding: .utf8) }
            #expect(bodyString?.contains("mixed-port") == true)
            #expect(bodyString?.contains("9091") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)
        try await client.patchConfig(partial: ["mixed-port": 9091])

        // Test passes if no error thrown
    }

    @Test("throws proxyNotFound when proxy does not exist")
    func testProxyNotFoundError() async throws {
        setupMock()

        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let mockSession = URLSession.makeMockSession()

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "{\"message\": \"Proxy 'NonExistent' not found\"}".data(using: .utf8)!
            return (response, data)
        }

        let client = MihomoAPIClient(baseURL: baseURL, urlSession: mockSession)

        await #expect(throws: MihomoAPIError.proxyNotFound("NonExistent")) {
            _ = try await client.testProxyDelay(name: "NonExistent", url: "https://www.google.com", timeout: 5000)
        }
    }
}
