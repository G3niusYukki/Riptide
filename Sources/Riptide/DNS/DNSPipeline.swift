import Foundation

public enum DNSQueryMode: Sendable {
    case fakeIP
    case realIP
}

public struct DNSConfig: Sendable {
    public let remoteServers: [String]
    public let directServers: [String]
    public let doHEndpoints: [String]
    public let mode: DNSQueryMode
    public let fakeIPCIDR: String
    public let cacheEnabled: Bool

    public init(
        remoteServers: [String] = ["8.8.8.8", "1.1.1.1"],
        directServers: [String] = ["223.5.5.5"],
        doHEndpoints: [String] = ["https://dns.google/dns-query", "https://1.1.1.1/dns-query"],
        mode: DNSQueryMode = .fakeIP,
        fakeIPCIDR: String = "198.18.0.0/16",
        cacheEnabled: Bool = true
    ) {
        self.remoteServers = remoteServers
        self.directServers = directServers
        self.doHEndpoints = doHEndpoints
        self.mode = mode
        self.fakeIPCIDR = fakeIPCIDR
        self.cacheEnabled = cacheEnabled
    }
}

public actor DNSPipeline {
    private let config: DNSConfig
    private let cache: DNSCache
    private let fakeIPPool: FakeIPPool
    private let ruleEngine: RuleEngine?

    private let udpClient: UDPDNSClient
    private let doHClient: DoHClient

    public init(config: DNSConfig = DNSConfig(), ruleEngine: RuleEngine? = nil) {
        self.config = config
        self.cache = DNSCache()
        self.fakeIPPool = FakeIPPool(cidr: config.fakeIPCIDR)
        self.ruleEngine = ruleEngine
        self.udpClient = UDPDNSClient()
        self.doHClient = DoHClient()
    }

    public func resolve(_ domain: String, type: DNSRecordType = .a) async throws -> [String] {
        if config.cacheEnabled {
            if let cached = await cache.get(name: domain, type: type) {
                return cached.compactMap { $0.addressString }
            }
        }

        let shouldUseRemote = await shouldResolveViaProxy(domain: domain)
        let servers = shouldUseRemote ? config.remoteServers : config.directServers

        var records: [DNSResourceRecord] = []
        var lastError: Error?

        for server in servers {
            let client = UDPDNSClient(serverHost: server)
            do {
                let response = try await client.query(name: domain, type: type, id: UInt16.random(in: 1...65535))
                if response.header.responseCode == .noError && !response.answers.isEmpty {
                    records = response.answers
                    break
                }
                lastError = DNSError.serverError("DNS response code: \(response.header.responseCode)")
            } catch {
                lastError = error
                continue
            }
        }

        if records.isEmpty {
            if let dohURL = config.doHEndpoints.first, let url = URL(string: dohURL) {
                let doh = DoHClient(serverURL: url)
                let response = try await doh.query(name: domain, type: type, id: UInt16.random(in: 1...65535))
                if response.header.responseCode == .noError {
                    records = response.answers
                }
            }
        }

        if records.isEmpty {
            throw lastError ?? DNSError.noRecords
        }

        if config.cacheEnabled {
            await cache.set(name: domain, type: type, records: records)
        }

        return records.compactMap { $0.addressString }
    }

    public func resolveFakeIP(_ domain: String) async throws -> String {
        if let existing = fakeIPPool.lookup(domain: domain) {
            return existing
        }
        guard let fakeIP = fakeIPPool.allocate(domain: domain) else {
            throw DNSError.serverError("fake-ip pool exhausted")
        }
        return fakeIP
    }

    public func reverseLookup(_ ip: String) -> String? {
        fakeIPPool.reverseLookup(ip: ip)
    }

    public func isFakeIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        let val = UInt32(parts[0]) << 24 | UInt32(parts[1]) << 16 | UInt32(parts[2]) << 8 | UInt32(parts[3])
        let base = UInt32(198) << 24 | UInt32(18) << 16
        return (val & 0xFFFF0000) == base
    }

    public func clearCache() {
        Task { await cache.clear() }
    }

    private func shouldResolveViaProxy(domain: String) async -> Bool {
        guard let engine = ruleEngine else { return false }
        let target = RuleTarget(domain: domain, ipAddress: nil)
        let policy = engine.resolve(target: target)
        if case .proxyNode = policy { return true }
        return false
    }
}
