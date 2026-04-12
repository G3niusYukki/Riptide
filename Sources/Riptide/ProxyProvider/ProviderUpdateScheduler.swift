import Foundation

public actor ProviderUpdateScheduler {
    public struct ScheduledUpdate: Sendable {
        public let providerID: UUID
        public let interval: TimeInterval
        public let nextUpdate: Date
    }
    
    private var schedules: [UUID: ScheduledUpdate] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let updateHandler: (UUID) async -> Void
    
    public init(updateHandler: @escaping (UUID) async -> Void) {
        self.updateHandler = updateHandler
    }
    
    public func schedule(providerID: UUID, interval: TimeInterval) {
        // Cancel existing schedule
        cancel(providerID: providerID)
        
        let schedule = ScheduledUpdate(
            providerID: providerID,
            interval: interval,
            nextUpdate: Date().addingTimeInterval(interval)
        )
        schedules[providerID] = schedule
        
        // Create periodic task
        tasks[providerID] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await updateHandler(providerID)
            }
        }
    }
    
    public func cancel(providerID: UUID) {
        tasks[providerID]?.cancel()
        tasks.removeValue(forKey: providerID)
        schedules.removeValue(forKey: providerID)
    }
    
    public func updateAll() async {
        for providerID in schedules.keys {
            await updateHandler(providerID)
        }
    }
    
    public func getSchedule(for providerID: UUID) -> ScheduledUpdate? {
        schedules[providerID]
    }
    
    public func stopAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        schedules.removeAll()
    }
}
