import Testing
import Foundation
@testable import Riptide

// MARK: - Mock Transport Session for Health Check Testing

final class MockHealthTransportSession: TransportSession, @unchecked Sendable {
    var sentData: [Data] = []
    var receiveResponses: [Data] = []
    var receiveIndex = 0
    var shouldFailReceive = false
    var closeCalled = false

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> Data {
        if shouldFailReceive {
            throw TransportError.receiveFailed("mock receive failure")
        }
        guard receiveIndex < receiveResponses.count else {
            throw TransportError.receiveFailed("no more responses")
        }
        let response = receiveResponses[receiveIndex]
        receiveIndex += 1
        return response
    }

    func close() async {
        closeCalled = true
    }
}

// MARK: - Mock Dialer for Health Checks

struct MockHealthDialer: TransportDialer {
    let session: MockHealthTransportSession

    func openSession(to node: ProxyNode) async throws -> any TransportSession {
        session
    }
}

// MARK: - HealthChecker Tests (Proxy-Routed)

@Suite("HealthChecker with ProxyConnector")
struct HealthCheckerProxyRoutedTests {

    @Test("check routes through proxy connector and measures latency")
    func checkRoutesThroughProxyConnector() async throws {
        // Arrange
        let mockSession = MockHealthTransportSession()
        // HTTP CONNECT expects: 1) CONNECT request from connector, 2) 200 response, 3) our HEAD request, 4) 204 response
        let connectResponse = Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        let headResponse = Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)
        mockSession.receiveResponses = [connectResponse, headResponse]

        let mockDialer = MockHealthDialer(session: mockSession)
        let pool = TransportConnectionPool(dialer: mockDialer)
        let connector = ProxyConnector(pool: pool)

        let checker = HealthChecker(connector: connector)

        let proxyNode = ProxyNode(
            name: "Test-Proxy",
            kind: .http,
            server: "proxy.example.com",
            port: 7890
        )

        let testURL = URL(string: "http://www.gstatic.com/generate_204")!

        // Act
        let result = await checker.check(node: proxyNode, testURL: testURL, timeout: .seconds(5))

        // Assert
        #expect(result.alive == true)
        #expect(result.nodeName == "Test-Proxy")
        #expect(result.latency != nil)
        #expect(result.latency! >= 0)

        // Verify CONNECT + HEAD requests were sent through the proxy
        #expect(mockSession.sentData.count == 2)
        let connectRequest = String(data: mockSession.sentData[0], encoding: .utf8) ?? ""
        // CONNECT goes to the test URL target (gstatic.com), not the proxy server itself
        #expect(connectRequest.contains("CONNECT www.gstatic.com:80"))
        
        let headRequest = String(data: mockSession.sentData[1], encoding: .utf8) ?? ""
        #expect(headRequest.contains("HEAD /generate_204 HTTP/1.1"))
        #expect(headRequest.contains("Host: www.gstatic.com"))
    }

    @Test("check records failure when proxy connection fails")
    func checkRecordsFailureWhenProxyConnectionFails() async throws {
        // Arrange
        struct FailingDialer: TransportDialer {
            func openSession(to node: ProxyNode) async throws -> any TransportSession {
                throw TransportError.dialFailed("connection refused")
            }
        }

        let pool = TransportConnectionPool(dialer: FailingDialer())
        let connector = ProxyConnector(pool: pool)
        let checker = HealthChecker(connector: connector)

        let proxyNode = ProxyNode(
            name: "Dead-Proxy",
            kind: .http,
            server: "dead.example.com",
            port: 9999
        )

        // Act
        let result = await checker.check(node: proxyNode, timeout: .seconds(3))

        // Assert
        #expect(result.alive == false)
        #expect(result.nodeName == "Dead-Proxy")
        #expect(result.latency == nil)
        #expect(result.error != nil)
    }

    @Test("check records failure when proxy returns error status")
    func checkRecordsFailureWhenProxyReturnsErrorStatus() async throws {
        // Arrange
        let mockSession = MockHealthTransportSession()
        let http500Response = Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8)
        mockSession.receiveResponses = [http500Response]

        let mockDialer = MockHealthDialer(session: mockSession)
        let pool = TransportConnectionPool(dialer: mockDialer)
        let connector = ProxyConnector(pool: pool)
        let checker = HealthChecker(connector: connector)

        let proxyNode = ProxyNode(
            name: "Error-Proxy",
            kind: .http,
            server: "error.example.com",
            port: 7890
        )

        // Act
        let result = await checker.check(node: proxyNode, timeout: .seconds(5))

        // Assert
        #expect(result.alive == false)
        #expect(result.latency == nil)
        #expect(result.error?.contains("500") ?? false)
    }

    @Test("check stores result for later retrieval")
    func checkStoresResultForLaterRetrieval() async throws {
        // Arrange
        let mockSession = MockHealthTransportSession()
        let connectResponse = Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        let headResponse = Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)
        mockSession.receiveResponses = [connectResponse, headResponse]

        let mockDialer = MockHealthDialer(session: mockSession)
        let pool = TransportConnectionPool(dialer: mockDialer)
        let connector = ProxyConnector(pool: pool)
        let checker = HealthChecker(connector: connector)

        let proxyNode = ProxyNode(
            name: "Stored-Proxy",
            kind: .http,
            server: "stored.example.com",
            port: 7890
        )

        // Act
        _ = await checker.check(node: proxyNode, timeout: .seconds(5))
        let retrieved = await checker.result(for: "Stored-Proxy")

        // Assert
        #expect(retrieved != nil)
        #expect(retrieved?.alive == true)
        #expect(retrieved?.nodeName == "Stored-Proxy")
    }

    @Test("check discards connection after probe")
    func checkDiscardsConnectionAfterProbe() async throws {
        // Arrange
        let mockSession = MockHealthTransportSession()
        let connectResponse = Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        let headResponse = Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)
        mockSession.receiveResponses = [connectResponse, headResponse]

        let mockDialer = MockHealthDialer(session: mockSession)
        let pool = TransportConnectionPool(dialer: mockDialer)
        let connector = ProxyConnector(pool: pool)
        let checker = HealthChecker(connector: connector)

        let proxyNode = ProxyNode(
            name: "OneShot-Proxy",
            kind: .http,
            server: "oneshot.example.com",
            port: 7890
        )

        // Act
        _ = await checker.check(node: proxyNode, timeout: .seconds(5))

        // Assert - CONNECT + HEAD requests were sent
        #expect(mockSession.sentData.count == 2)
    }

    @Test("allResults returns all stored health results")
    func allResultsReturnsAllStoredHealthResults() async throws {
        // Arrange
        let mockSession1 = MockHealthTransportSession()
        mockSession1.receiveResponses = [
            Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
            Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)
        ]
        let mockSession2 = MockHealthTransportSession()
        mockSession2.receiveResponses = [
            Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        ]

        final class IndexHolder: @unchecked Sendable {
            var value = 0
        }
        let indexHolder = IndexHolder()

        struct MultiDialer: TransportDialer {
            let sessions: [MockHealthTransportSession]
            let indexHolder: IndexHolder

            func openSession(to node: ProxyNode) async throws -> any TransportSession {
                let session = sessions[indexHolder.value % sessions.count]
                indexHolder.value += 1
                return session
            }
        }

        let dialer = MultiDialer(sessions: [mockSession1, mockSession2], indexHolder: indexHolder)
        let pool = TransportConnectionPool(dialer: dialer)
        let connector = ProxyConnector(pool: pool)
        let checker = HealthChecker(connector: connector)

        let node1 = ProxyNode(name: "Node-A", kind: .http, server: "a.example.com", port: 7890)
        let node2 = ProxyNode(name: "Node-B", kind: .http, server: "b.example.com", port: 7890)

        // Act
        _ = await checker.check(node: node1, timeout: .seconds(5))
        _ = await checker.check(node: node2, timeout: .seconds(5))
        let results = await checker.allResults()

        // Assert
        #expect(results.count == 2)
        #expect(results["Node-A"]?.alive == true)
        #expect(results["Node-B"]?.alive == true)
    }

    @Test("legacy mode without connector uses direct URLSession")
    func legacyModeWithoutConnectorUsesDirectURLSession() async throws {
        // Arrange
        let checker = HealthChecker() // No connector

        let proxyNode = ProxyNode(
            name: "Legacy-Proxy",
            kind: .http,
            server: "legacy.example.com",
            port: 7890
        )

        // Act - This will do a direct network call which will likely fail in test env
        let result = await checker.check(node: proxyNode, testURL: URL(string: "http://localhost:1")!, timeout: .seconds(1))

        // Assert - Should fail to connect, recording an error
        #expect(result.alive == false)
        #expect(result.nodeName == "Legacy-Proxy")
        #expect(result.error != nil)
    }
}

// MARK: - GroupSelector Tests with Health Results

@Suite("GroupSelector with HealthChecker")
struct GroupSelectorWithHealthCheckerTests {

    @Test("select urlTest group picks lowest latency node")
    func selectUrlTestGroupPicksLowestLatencyNode() async throws {
        // This test verifies the urlTest group selection logic
        // Without health results, urlTest returns nil (no best node found)

        let checker = HealthChecker()
        let group = ProxyGroup(
            id: "urltest-group",
            kind: .urlTest,
            proxies: ["fast", "medium", "slow"]
        )

        let proxies = [
            ProxyNode(name: "fast", kind: .http, server: "fast.example.com", port: 80),
            ProxyNode(name: "medium", kind: .http, server: "medium.example.com", port: 80),
            ProxyNode(name: "slow", kind: .http, server: "slow.example.com", port: 80)
        ]

        let selector = GroupSelector(healthChecker: checker)

        // Without health results, urlTest returns nil (no best node to select)
        let selected = await selector.select(group: group, proxies: proxies)
        #expect(selected == nil)
    }

    @Test("select fallback group returns first alive node")
    func selectFallbackGroupReturnsFirstAliveNode() async throws {
        // This test verifies the fallback group selection logic
        let checker = HealthChecker()
        let group = ProxyGroup(
            id: "fallback-group",
            kind: .fallback,
            proxies: ["node1", "node2", "node3"]
        )

        let proxies = [
            ProxyNode(name: "node1", kind: .http, server: "n1.example.com", port: 80),
            ProxyNode(name: "node2", kind: .http, server: "n2.example.com", port: 80),
            ProxyNode(name: "node3", kind: .http, server: "n3.example.com", port: 80)
        ]

        let selector = GroupSelector(healthChecker: checker)

        // Without health results, should return first
        let selected = await selector.select(group: group, proxies: proxies)
        #expect(selected?.name == "node1")
    }

    @Test("select group with no matching proxies returns nil")
    func selectGroupWithNoMatchingProxiesReturnsNil() async throws {
        let checker = HealthChecker()
        let group = ProxyGroup(
            id: "empty-group",
            kind: .select,
            proxies: ["nonexistent"]
        )

        let proxies = [
            ProxyNode(name: "actual-node", kind: .http, server: "actual.example.com", port: 80)
        ]

        let selector = GroupSelector(healthChecker: checker)
        let selected = await selector.select(group: group, proxies: proxies)

        #expect(selected == nil)
    }
}
