import Foundation

/// A bounded, in-memory event store for runtime diagnostics.
/// Keeps recent lifecycle events, connection snapshots, and throughput counters.
public actor RuntimeEventStore {
    private var events: [RuntimeEventEntry]
    private var connectionSnapshots: [RuntimeConnectionSnapshot]
    private var throughput: ThroughputCounter
    private let maxEvents: Int
    private let maxConnections: Int

    public struct ThroughputCounter: Sendable, Equatable {
        public var bytesUp: UInt64
        public var bytesDown: UInt64
        public var totalConnections: Int

        public init(bytesUp: UInt64 = 0, bytesDown: UInt64 = 0, totalConnections: Int = 0) {
            self.bytesUp = bytesUp
            self.bytesDown = bytesDown
            self.totalConnections = totalConnections
        }

        public mutating func add(up: UInt64, down: UInt64) {
            bytesUp += up
            bytesDown += down
        }

        public mutating func incrementConnections() {
            totalConnections += 1
        }
    }

    public struct RuntimeEventEntry: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let timestamp: Date
        public let event: RuntimeEvent

        public init(event: RuntimeEvent) {
            self.id = UUID()
            self.timestamp = Date()
            self.event = event
        }

        public static func == (lhs: RuntimeEventEntry, rhs: RuntimeEventEntry) -> Bool {
            lhs.id == rhs.id && lhs.event == rhs.event
        }
    }

    public init(maxEvents: Int = 500, maxConnections: Int = 100) {
        self.events = []
        self.connectionSnapshots = []
        self.throughput = ThroughputCounter()
        self.maxEvents = maxEvents
        self.maxConnections = maxConnections
    }

    // MARK: - Event Ingestion

    /// Record a runtime event.
    public func record(_ event: RuntimeEvent) {
        let entry = RuntimeEventEntry(event: event)
        events.append(entry)
        if events.count > maxEvents {
            events.removeFirst()
        }

        // Update throughput counters for connection events.
        switch event {
        case .connectionOpened(let snapshot):
            connectionSnapshots.append(snapshot)
            if connectionSnapshots.count > maxConnections {
                connectionSnapshots.removeFirst()
            }
            throughput.incrementConnections()

        case .connectionClosed:
            break

        default:
            break
        }
    }

    /// Record a connection opened event with transfer stats.
    public func recordConnectionOpened(_ snapshot: RuntimeConnectionSnapshot, up: UInt64, down: UInt64) {
        let entry = RuntimeEventEntry(event: .connectionOpened(snapshot))
        events.append(entry)
        if events.count > maxEvents {
            events.removeFirst()
        }
        connectionSnapshots.append(snapshot)
        if connectionSnapshots.count > maxConnections {
            connectionSnapshots.removeFirst()
        }
        throughput.add(up: up, down: down)
        throughput.incrementConnections()
    }

    /// Record throughput update.
    public func recordThroughput(up: UInt64, down: UInt64) {
        throughput.add(up: up, down: down)
    }

    // MARK: - Query

    /// Recent events (newest last).
    public func recentEvents(limit: Int = 100) -> [RuntimeEventEntry] {
        Array(events.suffix(limit))
    }

    /// Recent connection snapshots.
    public func recentConnections(limit: Int = 50) -> [RuntimeConnectionSnapshot] {
        Array(connectionSnapshots.suffix(limit))
    }

    /// Current throughput counter.
    public func currentThroughput() -> ThroughputCounter {
        throughput
    }

    /// Aggregate snapshot of all observable state.
    public func aggregateSnapshot() -> ObservableSnapshot {
        ObservableSnapshot(
            events: Array(events.suffix(maxEvents)),
            connections: Array(connectionSnapshots.suffix(maxConnections)),
            throughput: throughput
        )
    }

    /// Clear all buffered state.
    public func clear() {
        events.removeAll()
        connectionSnapshots.removeAll()
        throughput = ThroughputCounter()
    }
}

/// Full snapshot of observable runtime state.
public struct ObservableSnapshot: Sendable, Equatable {
    public let events: [RuntimeEventStore.RuntimeEventEntry]
    public let connections: [RuntimeConnectionSnapshot]
    public let throughput: RuntimeEventStore.ThroughputCounter

    public init(
        events: [RuntimeEventStore.RuntimeEventEntry],
        connections: [RuntimeConnectionSnapshot],
        throughput: RuntimeEventStore.ThroughputCounter
    ) {
        self.events = events
        self.connections = connections
        self.throughput = throughput
    }
}
