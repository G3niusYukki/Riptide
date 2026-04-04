import Foundation

// MARK: - Traffic Data Types

/// A single data point for traffic measurement
public struct TrafficDataPoint: Equatable, Sendable {
    public let timestamp: TimeInterval
    public let up: Int
    public let down: Int
    public let upSpeed: Double  // bytes per second
    public let downSpeed: Double  // bytes per second

    public init(
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        up: Int,
        down: Int,
        upSpeed: Double = 0,
        downSpeed: Double = 0
    ) {
        self.timestamp = timestamp
        self.up = up
        self.down = down
        self.upSpeed = upSpeed
        self.downSpeed = downSpeed
    }
}

/// Aggregated traffic statistics
public struct TrafficStatistics: Equatable, Sendable {
    public private(set) var totalUp: Int = 0
    public private(set) var totalDown: Int = 0

    public var totalBytes: Int {
        totalUp + totalDown
    }

    public init() {}

    public mutating func add(up: Int, down: Int) {
        totalUp += up
        totalDown += down
    }

    public mutating func reset() {
        totalUp = 0
        totalDown = 0
    }
}

// MARK: - Traffic Provider Protocol

/// Protocol for fetching traffic data from API
public protocol TrafficProvider: Sendable {
    func getTraffic() async throws -> (up: Int, down: Int)
}

// MARK: - Traffic ViewModel

/// Actor-based view model for traffic monitoring
public actor TrafficViewModel {
    // MARK: - State
    public private(set) var history: [TrafficDataPoint] = []
    public private(set) var totalTraffic = TrafficStatistics()
    public private(set) var peakUploadSpeed: Double = 0
    public private(set) var peakDownloadSpeed: Double = 0
    public private(set) var lastError: Error?

    // MARK: - Configuration
    public let maxHistoryPoints = 60
    private var lastTraffic: (up: Int, down: Int)?
    private var lastTimestamp: Date?

    // MARK: - Dependencies
    private let apiClient: TrafficProvider?

    // MARK: - Initialization
    public init(apiClient: TrafficProvider? = nil) {
        self.apiClient = apiClient
    }

    // MARK: - Data Recording
    @discardableResult
    public func recordTraffic(up: Int, down: Int) -> TrafficDataPoint {
        let now = Date()

        // Calculate speeds if we have previous data
        var upSpeed: Double = 0
        var downSpeed: Double = 0

        if let last = lastTraffic,
           let lastTime = lastTimestamp {
            let timeDelta = now.timeIntervalSince(lastTime)
            if timeDelta > 0 {
                upSpeed = Double(up - last.up) / timeDelta
                downSpeed = Double(down - last.down) / timeDelta

                // Handle overflow/reset (when mihomo restarts)
                if upSpeed < 0 { upSpeed = 0 }
                if downSpeed < 0 { downSpeed = 0 }
            }
        }

        let dataPoint = TrafficDataPoint(
            timestamp: now.timeIntervalSince1970,
            up: up,
            down: down,
            upSpeed: upSpeed,
            downSpeed: downSpeed
        )

        // Update state
        history.append(dataPoint)
        if history.count > maxHistoryPoints {
            history.removeFirst(history.count - maxHistoryPoints)
        }

        // Update peaks
        peakUploadSpeed = max(peakUploadSpeed, upSpeed)
        peakDownloadSpeed = max(peakDownloadSpeed, downSpeed)

        // Update totals (use delta from last measurement)
        if let last = lastTraffic {
            let upDelta = max(0, up - last.up)
            let downDelta = max(0, down - last.down)
            totalTraffic.add(up: upDelta, down: downDelta)
        }

        // Store for next calculation
        lastTraffic = (up: up, down: down)
        lastTimestamp = now

        return dataPoint
    }

    // MARK: - API Integration
    public func fetchTrafficFromAPI() async {
        guard let apiClient = apiClient else {
            lastError = TrafficError.noAPIClient
            return
        }

        do {
            let traffic = try await apiClient.getTraffic()
            recordTraffic(up: traffic.up, down: traffic.down)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    // MARK: - Formatting
    public func formatBytes(_ bytes: Int) -> String {
        let absBytes = abs(bytes)
        let sign = bytes < 0 ? "-" : ""

        switch absBytes {
        case 0:
            return "0 B"
        case 1..<1024:
            return "\(sign)\(absBytes) B"
        case 1024..<(1024 * 1024):
            return String(format: "\(sign)%.1f KB", Double(absBytes) / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "\(sign)%.1f MB", Double(absBytes) / (1024.0 * 1024.0))
        default:
            return String(format: "\(sign)%.1f GB", Double(absBytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }

    public func formatSpeed(_ bytesPerSecond: Double) -> String {
        let absSpeed = abs(bytesPerSecond)
        let sign = bytesPerSecond < 0 ? "-" : ""

        switch absSpeed {
        case 0:
            return "0 B/s"
        case 1..<1024:
            return String(format: "\(sign)%.0f B/s", absSpeed)
        case 1024..<(1024 * 1024):
            return String(format: "\(sign)%.1f KB/s", absSpeed / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "\(sign)%.1f MB/s", absSpeed / (1024.0 * 1024.0))
        default:
            return String(format: "\(sign)%.1f GB/s", absSpeed / (1024.0 * 1024.0 * 1024.0))
        }
    }

    public func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%d sec", Int(seconds))
        } else if seconds < 3600 {
            return String(format: "%d min", Int(seconds / 60))
        } else {
            return String(format: "%d hr", Int(seconds / 3600))
        }
    }

    // MARK: - Control
    public func reset() {
        history.removeAll()
        totalTraffic.reset()
        peakUploadSpeed = 0
        peakDownloadSpeed = 0
        lastTraffic = nil
        lastTimestamp = nil
        lastError = nil
    }

    // MARK: - Queries
    public func currentSpeed() -> (up: Double, down: Double) {
        guard let last = history.last else {
            return (up: 0, down: 0)
        }
        return (up: last.upSpeed, down: last.downSpeed)
    }

    public func averageSpeed() -> (up: Double, down: Double) {
        guard !history.isEmpty else {
            return (up: 0, down: 0)
        }

        let totalUp = history.reduce(0) { $0 + $1.upSpeed }
        let totalDown = history.reduce(0) { $0 + $1.downSpeed }
        let count = Double(history.count)

        return (up: totalUp / count, down: totalDown / count)
    }
}

// MARK: - Traffic Error

public enum TrafficError: Error, Equatable, Sendable {
    case noAPIClient
    case networkError(String)
    case invalidResponse
}
