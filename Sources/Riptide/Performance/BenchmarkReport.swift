import Foundation

public struct BenchmarkReport: Sendable {
    public let results: BenchmarkResults
    public let target: String
    public let commit: String

    public init(results: BenchmarkResults, target: String, commit: String) {
        self.results = results
        self.target = target
        self.commit = commit
    }

    public func renderMarkdown() -> String {
        """
        | Metric | Value |
        |--------|-------|
        | Target | \(target) |
        | Commit | \(commit) |
        | HTTP CONNECT p50 | \(results.httpConnectLatency.p50Micros) µs |
        | HTTP CONNECT p99 | \(results.httpConnectLatency.p99Micros) µs |
        | Throughput | \(results.throughputRequestsPerSecond) req/s |
        | Idle memory | \(results.idleMemoryBytes / 1024) KiB |
        | CPU | \(String(format: "%.1f", results.cpuPercent))% |
        | Startup | \(results.startupMilliseconds) ms |
        """
    }
}
