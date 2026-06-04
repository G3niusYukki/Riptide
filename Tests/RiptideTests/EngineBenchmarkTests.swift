import XCTest
@testable import Riptide

final class EngineBenchmarkTests: XCTestCase {
    func test_benchmark_run_returns_populated_results() async throws {
        // Use a tiny iteration count so the test stays under 1 second
        // in CI. Production runs use 1000+ iterations.
        let config = BenchmarkConfig(
            httpConnectIterations: 3,
            concurrencyLevel: 2,
            warmupDuration: .zero
        )
        let harness = EngineBenchmark(config: config, target: .loopbackStub)
        let results = try await harness.run()

        XCTAssertGreaterThanOrEqual(results.httpConnectLatency.p50Micros, 0)
        XCTAssertGreaterThanOrEqual(results.httpConnectLatency.p99Micros, 0)
        XCTAssertGreaterThanOrEqual(results.idleMemoryBytes, 0)
        XCTAssertGreaterThanOrEqual(results.startupMilliseconds, 0)
    }

    func test_benchmark_report_renders_markdown_with_required_fields() async throws {
        let config = BenchmarkConfig(
            httpConnectIterations: 1,
            concurrencyLevel: 1,
            warmupDuration: .zero
        )
        let results = try await EngineBenchmark(config: config, target: .loopbackStub).run()
        let report = BenchmarkReport(results: results, target: "Swift Engine", commit: "local")
        let markdown = report.renderMarkdown()

        XCTAssertTrue(markdown.contains("HTTP CONNECT p50"))
        XCTAssertTrue(markdown.contains("Idle memory"))
        XCTAssertTrue(markdown.contains("Startup"))
        XCTAssertTrue(markdown.contains("Swift Engine"))
    }
}
