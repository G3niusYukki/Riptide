import Foundation
import Testing
@testable import Riptide

// MARK: - Traffic Chart Tests

@Suite("Traffic Chart")
struct TrafficChartTests {

    @Test("records traffic data point")
    func testRecordTrafficDataPoint() async throws {
        let viewModel = TrafficViewModel()

        let dataPoint = try await viewModel.recordTraffic(up: 1024, down: 2048)

        #expect(dataPoint.up == 1024)
        #expect(dataPoint.down == 2048)
        #expect(dataPoint.timestamp > 0)
    }

    @Test("calculates speed from traffic delta")
    func testCalculateSpeedFromDelta() async throws {
        let viewModel = TrafficViewModel()

        // First measurement: 1000 bytes total
        try await viewModel.recordTraffic(up: 500, down: 500)

        // Wait a small amount to simulate time passing
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Second measurement: 3000 bytes total (2000 bytes difference)
        let dataPoint = try await viewModel.recordTraffic(up: 1500, down: 1500)

        // Speed should be approximately 20000 bytes/second (2000 bytes / 0.1s)
        #expect(dataPoint.upSpeed > 0)
        #expect(dataPoint.downSpeed > 0)
    }

    @Test("maintains max 60 data points")
    func testMaintainsMax60DataPoints() async throws {
        let viewModel = TrafficViewModel()

        // Add 70 data points
        for i in 0..<70 {
            try await viewModel.recordTraffic(up: i * 100, down: i * 200)
        }

        let history = await viewModel.history
        #expect(history.count <= 60)
    }

    @Test("calculates total traffic")
    func testCalculatesTotalTraffic() async throws {
        let viewModel = TrafficViewModel()

        // First measurement sets baseline
        try await viewModel.recordTraffic(up: 1024, down: 2048)
        // Second measurement accumulates delta
        try await viewModel.recordTraffic(up: 1536, down: 3072)

        let total = await viewModel.totalTraffic
        #expect(total.totalUp == 512)
        #expect(total.totalDown == 1024)
    }

    @Test("formats bytes to human readable")
    func testFormatsBytesToHumanReadable() async throws {
        let viewModel = TrafficViewModel()

        #expect(await viewModel.formatBytes(0) == "0 B")
        #expect(await viewModel.formatBytes(512) == "512 B")
        #expect(await viewModel.formatBytes(1024) == "1.0 KB")
        #expect(await viewModel.formatBytes(1536) == "1.5 KB")
        #expect(await viewModel.formatBytes(1024 * 1024) == "1.0 MB")
        #expect(await viewModel.formatBytes(1024 * 1024 * 1024) == "1.0 GB")
    }

    @Test("formats speed to human readable")
    func testFormatsSpeedToHumanReadable() async throws {
        let viewModel = TrafficViewModel()

        #expect(await viewModel.formatSpeed(0) == "0 B/s")
        #expect(await viewModel.formatSpeed(512) == "512 B/s")
        #expect(await viewModel.formatSpeed(10240) == "10.0 KB/s")
        #expect(await viewModel.formatSpeed(1024 * 1024) == "1.0 MB/s")
    }

    @Test("calculates peak speeds")
    func testCalculatesPeakSpeeds() async throws {
        let viewModel = TrafficViewModel()

        // Add data points with varying speeds
        try await viewModel.recordTraffic(up: 1000, down: 2000)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await viewModel.recordTraffic(up: 2000, down: 4000)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await viewModel.recordTraffic(up: 500, down: 1000)

        let peakUp = await viewModel.peakUploadSpeed
        let peakDown = await viewModel.peakDownloadSpeed

        #expect(peakUp > 0)
        #expect(peakDown > 0)
    }

    @Test("resets traffic statistics")
    func testResetsTrafficStatistics() async throws {
        let viewModel = TrafficViewModel()

        try await viewModel.recordTraffic(up: 1024, down: 2048)
        try await viewModel.reset()

        let total = await viewModel.totalTraffic
        let history = await viewModel.history

        #expect(total.totalUp == 0)
        #expect(total.totalDown == 0)
        #expect(history.isEmpty)
    }

    @Test("handles API traffic data")
    func testHandlesAPITrafficData() async throws {
        let mockAPI = MockTrafficAPI()
        let viewModel = TrafficViewModel(apiClient: mockAPI)

        // First call sets baseline
        await mockAPI.setNextTraffic(up: 1000, down: 2000)
        await viewModel.fetchTrafficFromAPI()

        // Second call accumulates delta
        await mockAPI.setNextTraffic(up: 6000, down: 12000)
        await viewModel.fetchTrafficFromAPI()

        let total = await viewModel.totalTraffic
        #expect(total.totalUp == 5000)
        #expect(total.totalDown == 10000)
    }

    @Test("handles API errors gracefully")
    func testHandlesAPIErrors() async throws {
        let mockAPI = MockTrafficAPI(shouldFail: true)
        let viewModel = TrafficViewModel(apiClient: mockAPI)

        // Should not throw when API fails
        await viewModel.fetchTrafficFromAPI()

        // ViewModel should track error state
        let error = await viewModel.lastError
        #expect(error != nil)
    }
}

// MARK: - Traffic Data Point Tests

@Suite("Traffic Data Point")
struct TrafficDataPointTests {

    @Test("calculates correct timestamp")
    func testCalculatesCorrectTimestamp() {
        let before = Date().timeIntervalSince1970
        let dataPoint = TrafficDataPoint(up: 100, down: 200, upSpeed: 50, downSpeed: 100)
        let after = Date().timeIntervalSince1970

        #expect(dataPoint.timestamp >= before)
        #expect(dataPoint.timestamp <= after)
    }

    @Test("is sendable")
    func testIsSendable() {
        let dataPoint = TrafficDataPoint(up: 100, down: 200, upSpeed: 50, downSpeed: 100)
        // Compile-time check that TrafficDataPoint is Sendable
        Task {
            let _: TrafficDataPoint = dataPoint
        }
    }
}

// MARK: - Traffic Statistics Tests

@Suite("Traffic Statistics")
struct TrafficStatisticsTests {

    @Test("accumulates total traffic")
    func testAccumulatesTotalTraffic() {
        var stats = TrafficStatistics()

        stats.add(up: 1024, down: 2048)
        #expect(stats.totalUp == 1024)
        #expect(stats.totalDown == 2048)

        stats.add(up: 512, down: 1024)
        #expect(stats.totalUp == 1536)
        #expect(stats.totalDown == 3072)
    }

    @Test("calculates total bytes")
    func testCalculatesTotalBytes() {
        var stats = TrafficStatistics()
        stats.add(up: 1024, down: 2048)

        #expect(stats.totalBytes == 3072)
    }

    @Test("is equatable")
    func testIsEquatable() {
        var stats1 = TrafficStatistics()
        stats1.add(up: 100, down: 200)

        var stats2 = TrafficStatistics()
        stats2.add(up: 100, down: 200)

        var stats3 = TrafficStatistics()
        stats3.add(up: 200, down: 100)

        #expect(stats1 == stats2)
        #expect(stats1 != stats3)
    }
}

// MARK: - Mock Objects

private actor MockTrafficAPI: Riptide.TrafficProvider {
    private var nextUp: Int = 0
    private var nextDown: Int = 0
    private var failNext: Bool = false

    init(shouldFail: Bool = false) {
        self.failNext = shouldFail
    }

    func setNextTraffic(up: Int, down: Int) {
        self.nextUp = up
        self.nextDown = down
    }

    func getTraffic() async throws -> (up: Int, down: Int) {
        if failNext {
            throw TrafficAPIError.networkError
        }
        return (up: nextUp, down: nextDown)
    }
}

private enum TrafficAPIError: Error {
    case networkError
}
