import Foundation

struct DNSCacheEntry: Sendable {
    let records: [DNSResourceRecord]
    let expiresAt: ContinuousClock.Instant
}

public actor DNSCache {
    private var cache: [String: DNSCacheEntry]

    public init() {
        self.cache = [:]
    }

    private func cacheKey(_ name: String, _ type: DNSRecordType) -> String {
        "\(name.lowercased()):\(type.rawValue)"
    }

    public func get(name: String, type: DNSRecordType) -> [DNSResourceRecord]? {
        let key = cacheKey(name, type)
        guard let entry = cache[key] else { return nil }
        if ContinuousClock.now >= entry.expiresAt {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.records
    }

    public func set(name: String, type: DNSRecordType, records: [DNSResourceRecord], ttlOverride: UInt32? = nil) {
        let key = cacheKey(name, type)
        let minTTL = records.map { $0.ttl }.min() ?? 60
        let effectiveTTL = ttlOverride ?? min(minTTL, 3600)
        let entry = DNSCacheEntry(
            records: records,
            expiresAt: ContinuousClock.now + Duration.seconds(Int64(effectiveTTL))
        )
        cache[key] = entry
    }

    public func invalidate(name: String, type: DNSRecordType) {
        cache.removeValue(forKey: cacheKey(name, type))
    }

    public func clear() {
        cache.removeAll()
    }

    public func evictExpired() {
        let now = ContinuousClock.now
        cache = cache.filter { _, entry in now < entry.expiresAt }
    }
}
