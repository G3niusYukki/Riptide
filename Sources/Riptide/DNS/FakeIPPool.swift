import Foundation

public final class FakeIPPool: @unchecked Sendable {
    private struct Allocation: Sendable {
        let domain: String
        let allocatedAt: ContinuousClock.Instant
    }

    private let cidrBase: String
    private let prefixLength: Int
    private let maxAddresses: Int
    private let lifetime: Duration
    private let baseNumeric: UInt32

    private var allocations: [String: Allocation]
    private var reverseMap: [String: String]
    private var nextIndex: Int

    public init(cidr: String = "198.18.0.0/16", lifetime: Duration = .seconds(600)) {
        self.cidrBase = cidr
        self.lifetime = lifetime
        let parts = cidr.split(separator: "/")
        self.prefixLength = Int(parts[1]) ?? 16
        let hostBits = 32 - self.prefixLength
        self.maxAddresses = 1 << hostBits

        let ipParts = parts[0].split(separator: ".").compactMap { UInt32($0) }
        let base = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let mask = UInt32.max << hostBits
        self.baseNumeric = base & mask
        self.allocations = [:]
        self.reverseMap = [:]
        self.nextIndex = 0
    }

    public func allocate(domain: String) -> String? {
        let lower = domain.lowercased()
        if let existing = allocations[lower] {
            return existing.domain
        }

        if nextIndex >= maxAddresses {
            evictExpired()
        }
        if nextIndex >= maxAddresses {
            return nil
        }

        let ip = baseNumeric | UInt32(nextIndex + 1)
        nextIndex += 1
        let ipString = "\(UInt8(ip >> 24 & 0xFF)).\(UInt8(ip >> 16 & 0xFF)).\(UInt8(ip >> 8 & 0xFF)).\(UInt8(ip & 0xFF))"

        allocations[lower] = Allocation(domain: ipString, allocatedAt: ContinuousClock.now)
        reverseMap[ipString] = domain
        return ipString
    }

    public func lookup(domain: String) -> String? {
        let lower = domain.lowercased()
        return allocations[lower]?.domain
    }

    public func reverseLookup(ip: String) -> String? {
        reverseMap[ip]
    }

    private func evictExpired() {
        let now = ContinuousClock.now
        let expired = allocations.filter { _, entry in now - entry.allocatedAt >= lifetime }
        for (domain, entry) in expired {
            reverseMap.removeValue(forKey: entry.domain)
            allocations.removeValue(forKey: domain)
        }
    }
}
