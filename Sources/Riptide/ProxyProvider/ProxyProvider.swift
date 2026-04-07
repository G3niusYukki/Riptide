import Foundation

/// Error types for proxy provider operations.
public enum ProxyProviderError: Error, Sendable {
    case downloadFailed(underlying: Error)
    case parseError(String)
    case noURL
    case fileReadFailed(String)
    case invalidConfig(reason: String)
}

/// Actor that downloads and auto-updates a remote proxy provider.
public actor ProxyProvider {
    public let id: UUID
    public let config: ProxyProviderConfig
    private var currentNodes: [ProxyNode] = []
    private var updateTask: Task<Void, Never>?

    public init(config: ProxyProviderConfig) {
        self.id = UUID()
        self.config = config
    }

    /// Start periodic proxy list updates.
    public func start() async {
        try? await refresh()

        guard let interval = config.interval, interval > 0 else { return }

        updateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                try? await refresh()
            }
        }
    }

    /// Stop periodic updates.
    public func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    /// Returns the current proxy nodes.
    public func nodes() -> [ProxyNode] {
        currentNodes
    }

    /// Manually trigger a refresh.
    public func refresh() async throws {
        switch config.type.lowercased() {
        case "http":
            guard let urlStr = config.url else {
                return
            }
            do {
                let data = try await downloadData(from: urlStr)
                guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
                    return
                }
                let nodes = try parseProxies(content)
                currentNodes = nodes
            } catch {
                // Keep existing nodes on failure.
            }

        case "file":
            guard let pathStr = config.path else {
                throw ProxyProviderError.fileReadFailed("No path configured")
            }
            let url = URL(fileURLWithPath: pathStr)
            let content: String
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw ProxyProviderError.fileReadFailed("Failed to read file: \(error)")
            }
            guard !content.isEmpty else {
                throw ProxyProviderError.parseError("File is empty")
            }
            let nodes = try parseProxies(content)
            currentNodes = nodes

        default:
            // Unknown type, skip.
            throw ProxyProviderError.invalidConfig(reason: "Unknown provider type: \(config.type)")
        }
    }

    /// Download raw data from a URL using URLSession.
    private func downloadData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ProxyProviderError.downloadFailed(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Clash Verge Rev/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProxyProviderError.downloadFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        return data
    }

    /// Parse proxy URIs (ss://, vmess://, vless://, trojan://) or Clash YAML proxies list.
    private func parseProxies(_ content: String) throws -> [ProxyNode] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to detect Clash YAML format: contains "proxies:" anywhere.
        if trimmed.contains("proxies:") {
            return try parseClashYAML(trimmed)
        }

        // Otherwise, treat as URI list (possibly base64-encoded).
        return parseURIs(trimmed)
    }

    /// Parse a Clash YAML string containing a proxies list.
    private func parseClashYAML(_ yaml: String) throws -> [ProxyNode] {
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        return config.proxies
    }

    /// Parse raw URI lines (ss://, vmess://, vless://, trojan://), with optional base64 decoding.
    private func parseURIs(_ content: String) -> [ProxyNode] {
        var decoded = content

        // Try base64 decoding if it looks like a subscription blob.
        if let base64Data = Data(base64Encoded: content) {
            if let decodedStr = String(data: base64Data, encoding: .utf8) {
                decoded = decodedStr
            }
        }

        var nodes: [ProxyNode] = []
        var index = 0
        for line in decoded.components(separatedBy: "\n") {
            let uri = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard uri.hasPrefix("ss://") || uri.hasPrefix("vmess://") ||
                  uri.hasPrefix("vless://") || uri.hasPrefix("trojan://") else {
                continue
            }
            if let parsed = ProxyURIParser.parse(uri) {
                let decodedName = parsed.name.removingPercentEncoding ?? parsed.name
                nodes.append(ProxyNode(
                    name: decodedName.isEmpty ? "provider-\(index)" : decodedName,
                    kind: parsed.kind,
                    server: parsed.server,
                    port: parsed.port,
                    cipher: parsed.cipher,
                    password: parsed.password
                ))
                index += 1
            }
        }
        return nodes
    }
}
