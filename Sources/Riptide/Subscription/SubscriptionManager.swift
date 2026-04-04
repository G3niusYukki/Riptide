import Foundation

// MARK: - Subscription Update

/// Result of fetching a subscription
public struct SubscriptionUpdate: Sendable {
    public let nodes: [ProxyNode]
    public let updatedAt: Date
    public let source: URL

    public init(nodes: [ProxyNode], updatedAt: Date = Date(), source: URL) {
        self.nodes = nodes
        self.updatedAt = updatedAt
        self.source = source
    }
}

// MARK: - Subscription Error

public enum SubscriptionError: Error, Sendable {
    case invalidURL
    case fetchFailed(String)
    case parseFailed(String)
    case noNodes
}

// MARK: - Subscription Model

/// Represents a subscription to a remote proxy configuration
public struct Subscription: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var url: String
    public var autoUpdate: Bool
    public var updateInterval: TimeInterval  // in seconds, default 1 hour
    public var lastUpdated: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        autoUpdate: Bool = true,
        updateInterval: TimeInterval = 3600,
        lastUpdated: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.autoUpdate = autoUpdate
        self.updateInterval = updateInterval
        self.lastUpdated = lastUpdated
        self.lastError = lastError
    }

    /// Calculates the next update time based on last update and interval
    /// - Returns: The next update time, or nil if autoUpdate is disabled or never updated
    public var nextUpdateTime: Date? {
        guard autoUpdate else { return nil }
        // If never updated, return nil (meaning update immediately)
        guard let lastUpdated = lastUpdated else {
            return nil
        }
        return lastUpdated.addingTimeInterval(updateInterval)
    }

    /// Checks if the subscription needs an update
    public func needsUpdate(referenceDate: Date = Date()) -> Bool {
        guard autoUpdate else { return false }
        guard let nextUpdate = nextUpdateTime else { return true }
        return referenceDate >= nextUpdate
    }
}

// MARK: - Update Result

/// Result of a subscription update operation
public enum SubscriptionUpdateResult: Equatable, Sendable {
    case success(proxies: [ProxyNode])
    case failure(error: String)
    case noChange
}

// MARK: - Subscription Manager

/// Actor that manages subscriptions and their updates
public actor SubscriptionManager {
    private var subscriptions: [UUID: Subscription] = [:]
    private let storage: SubscriptionStorage

    public init(storage: SubscriptionStorage = UserDefaultsSubscriptionStorage()) {
        self.storage = storage
        // Load saved subscriptions
        Task {
            await loadSubscriptions()
        }
    }

    // MARK: - CRUD Operations

    /// Adds a new subscription
    public func addSubscription(
        name: String,
        url: String,
        autoUpdate: Bool = true,
        interval: TimeInterval = 3600
    ) -> Subscription {
        let subscription = Subscription(
            name: name,
            url: url,
            autoUpdate: autoUpdate,
            updateInterval: interval
        )
        subscriptions[subscription.id] = subscription
        Task {
            await saveSubscriptions()
        }
        return subscription
    }

    /// Removes a subscription by ID
    public func removeSubscription(id: UUID) {
        subscriptions.removeValue(forKey: id)
        Task {
            await saveSubscriptions()
        }
    }

    /// Returns a subscription by ID
    public func subscription(id: UUID) -> Subscription? {
        subscriptions[id]
    }

    /// Returns all subscriptions
    public func allSubscriptions() -> [Subscription] {
        Array(subscriptions.values)
    }

    /// Updates subscription properties
    public func updateSubscription(
        id: UUID,
        name: String? = nil,
        url: String? = nil,
        autoUpdate: Bool? = nil,
        interval: TimeInterval? = nil
    ) {
        guard var subscription = subscriptions[id] else { return }

        if let name = name { subscription.name = name }
        if let url = url { subscription.url = url }
        if let autoUpdate = autoUpdate { subscription.autoUpdate = autoUpdate }
        if let interval = interval { subscription.updateInterval = interval }

        subscriptions[id] = subscription
        Task {
            await saveSubscriptions()
        }
    }

    /// Records a successful update
    public func recordUpdateSuccess(id: UUID) {
        guard var subscription = subscriptions[id] else { return }
        subscription.lastUpdated = Date()
        subscription.lastError = nil
        subscriptions[id] = subscription
        Task {
            await saveSubscriptions()
        }
    }

    /// Records an update failure
    public func recordUpdateFailure(id: UUID, error: String) {
        guard var subscription = subscriptions[id] else { return }
        subscription.lastError = error
        subscriptions[id] = subscription
        Task {
            await saveSubscriptions()
        }
    }

    // MARK: - Update Scheduling

    /// Returns subscriptions that need updating
    public func subscriptionsNeedingUpdate(referenceDate: Date = Date()) -> [Subscription] {
        allSubscriptions().filter { $0.needsUpdate(referenceDate: referenceDate) }
    }

    /// Calculates next update time for a subscription
    public func nextUpdateTime(for id: UUID) -> Date? {
        subscription(id: id)?.nextUpdateTime
    }

    // MARK: - Fetch Operations

    /// Fetches and parses a subscription from a URL
    public func fetchSubscription(url: URL) async throws -> SubscriptionUpdate {
        guard let scheme = url.scheme, scheme == "https" || scheme == "http" else {
            throw SubscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Clash Verge Rev/2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SubscriptionError.fetchFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let nodes: [ProxyNode]

        if contentType.contains("yaml") || contentType.contains("text/plain") {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.hasPrefix("proxy") || text.contains("proxies:") {
                nodes = try parseClashYAML(text)
            } else {
                nodes = try parseBase64URIList(text)
            }
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            nodes = try parseBase64URIList(text)
        }

        guard !nodes.isEmpty else { throw SubscriptionError.noNodes }

        return SubscriptionUpdate(nodes: nodes, source: url)
    }

    /// Updates a subscription by fetching fresh data
    public func updateSubscription(id: UUID) async -> SubscriptionUpdateResult {
        guard let subscription = subscriptions[id] else {
            return .failure(error: "Subscription not found")
        }

        guard let url = URL(string: subscription.url) else {
            return .failure(error: "Invalid URL")
        }

        do {
            let update = try await fetchSubscription(url: url)
            await recordUpdateSuccess(id: id)
            return .success(proxies: update.nodes)
        } catch let error as SubscriptionError {
            let errorMessage = String(describing: error)
            await recordUpdateFailure(id: id, error: errorMessage)
            return .failure(error: errorMessage)
        } catch {
            let errorMessage = String(describing: error)
            await recordUpdateFailure(id: id, error: errorMessage)
            return .failure(error: errorMessage)
        }
    }

    // MARK: - Private Methods

    private func parseBase64URIList(_ text: String) throws -> [ProxyNode] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SubscriptionError.parseFailed("empty content") }

        let decoded: String
        if let base64 = Data(base64Encoded: trimmed) {
            decoded = String(data: base64, encoding: .utf8) ?? trimmed
        } else {
            decoded = trimmed
        }

        var nodes: [ProxyNode] = []
        var index = 0
        for line in decoded.components(separatedBy: "\n") {
            let uri = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard uri.hasPrefix("ss://") || uri.hasPrefix("vmess://") ||
                  uri.hasPrefix("vless://") || uri.hasPrefix("trojan://") else { continue }
            if let parsed = parseProxyURI(uri) {
                nodes.append(ProxyNode(
                    name: parsed.name.isEmpty ? "node-\(index)" : parsed.name,
                    kind: parsed.kind, server: parsed.server, port: parsed.port,
                    cipher: parsed.cipher, password: parsed.password
                ))
                index += 1
            }
        }
        return nodes
    }

    private func parseClashYAML(_ yaml: String) throws -> [ProxyNode] {
        do {
            let (config, _) = try ClashConfigParser.parse(yaml: yaml)
            return config.proxies
        } catch {
            throw SubscriptionError.parseFailed(String(describing: error))
        }
    }

    private func parseProxyURI(_ uri: String) -> ParsedProxy? {
        guard let (rest, fragment) = extractFragment(uri) else { return nil }

        if rest.hasPrefix("ss://") { return parseSS(String(rest.dropFirst(5)), fragment: fragment) }
        if rest.hasPrefix("vmess://") { return parseVMess(String(rest.dropFirst(8)), fragment: fragment) }
        if rest.hasPrefix("vless://") { return parseVLESS(String(rest.dropFirst(8)), fragment: fragment) }
        if rest.hasPrefix("trojan://") { return parseTrojan(String(rest.dropFirst(9)), fragment: fragment) }
        return nil
    }

    private func extractFragment(_ uri: String) -> (String, String)? {
        guard let hashIdx = uri.firstIndex(of: "#") else { return (uri, "") }
        let rest = String(uri[..<hashIdx])
        let fragment = String(uri[uri.index(after: hashIdx)...])
        return (rest, fragment)
    }

    private func parseSS(_ body: String, fragment: String) -> ParsedProxy? {
        let str = body
        let serverAndParams: String
        var method = ""
        var password = ""

        if let atIdx = str.firstIndex(of: "@") {
            let userInfo = String(str[..<atIdx])
            serverAndParams = String(str[str.index(after: atIdx)...])
            if let base64Data = Data(base64Encoded: userInfo.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
               let decoded = String(data: base64Data, encoding: .utf8),
               let colonIdx = decoded.firstIndex(of: ":") {
                method = String(decoded[..<colonIdx])
                password = String(decoded[decoded.index(after: colonIdx)...])
            }
        } else {
            if let base64Data = Data(base64Encoded: str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
               let decoded = String(data: base64Data, encoding: .utf8),
               let atIdx = decoded.firstIndex(of: "@") {
                let userInfo = String(decoded[..<atIdx])
                serverAndParams = String(decoded[decoded.index(after: atIdx)...])
                if let colonIdx = userInfo.firstIndex(of: ":") {
                    method = String(userInfo[..<colonIdx])
                    password = String(userInfo[userInfo.index(after: colonIdx)...])
                }
            } else {
                return nil
            }
        }

        guard let colonIdx = serverAndParams.lastIndex(of: ":") else { return nil }
        let host = String(serverAndParams[..<colonIdx])
        let portStr = String(serverAndParams[serverAndParams.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .shadowsocks, server: host, port: port, cipher: method, password: password)
    }

    private func parseVMess(_ body: String, fragment: String) -> ParsedProxy? {
        let padded = body.padding(toLength: ((body.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        guard let base64Data = Data(base64Encoded: padded),
              let decoded = String(data: base64Data, encoding: .utf8) else { return nil }

        guard let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let host = json["add"] as? String,
              let port = json["port"] as? Int else { return nil }

        return ParsedProxy(
            name: json["ps"] as? String ?? fragment,
            kind: .vmess, server: host, port: port,
            cipher: json["scy"] as? String,
            password: json["id"] as? String
        )
    }

    private func parseVLESS(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let uuid = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .vless, server: host, port: port, cipher: nil, password: uuid)
    }

    private func parseTrojan(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let password = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .trojan, server: host, port: port, cipher: nil, password: password)
    }

    private struct ParsedProxy {
        let name: String
        let kind: ProxyKind
        let server: String
        let port: Int
        let cipher: String?
        let password: String?
    }

    // MARK: - Persistence

    private func loadSubscriptions() async {
        do {
            let saved = try await storage.load()
            for sub in saved {
                subscriptions[sub.id] = sub
            }
        } catch {
            // Log but don't fail on load error
            print("[SubscriptionManager] Failed to load subscriptions: \(error)")
        }
    }

    private func saveSubscriptions() async {
        do {
            try await storage.save(Array(subscriptions.values))
        } catch {
            print("[SubscriptionManager] Failed to save subscriptions: \(error)")
        }
    }
}

// MARK: - Storage Protocol

/// Protocol for subscription persistence
public protocol SubscriptionStorage: Sendable {
    func load() async throws -> [Subscription]
    func save(_ subscriptions: [Subscription]) async throws
}

// MARK: - UserDefaults Storage

/// UserDefaults-based storage for subscriptions
public actor UserDefaultsSubscriptionStorage: SubscriptionStorage {
    private let key = "riptide.subscriptions"
    private let defaults = UserDefaults.standard

    public init() {}

    public func load() async throws -> [Subscription] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Subscription].self, from: data)
    }

    public func save(_ subscriptions: [Subscription]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(subscriptions)
        defaults.set(data, forKey: key)
    }
}
