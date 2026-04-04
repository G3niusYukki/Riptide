import Foundation

// MARK: - GeoSite Resolver

/// Resolves domain names to site categories using a GeoSite-style database.
///
/// GeoSite databases map domains to categorized site codes (e.g. "cn", "google", "apple").
/// A rule like `GEOSITE,cn,DIRECT` matches domains categorized under "cn".
///
/// This implementation uses a simple domain→categories mapping loaded from a JSON file.
/// A full implementation would use the v2ray domain dat format.
public struct GeoSiteResolver: Sendable {

    // MARK: - Errors

    public enum GeoSiteError: Error, Equatable, Sendable {
        case invalidFile(String)
        case parseError(String)

        public var localizedDescription: String {
            switch self {
            case .invalidFile(let msg): return "Invalid GeoSite file: \(msg)"
            case .parseError(let msg): return "GeoSite parse error: \(msg)"
            }
        }
    }

    // MARK: - Data Model

    /// A single site entry: domain → list of category codes.
    private struct SiteEntry: Codable {
        let domains: [String]
        let code: String
    }

    // MARK: - State

    /// Maps lowercase domain → set of site codes.
    private let domainToCodes: [String: Set<String>]

    // MARK: - Init

    /// Load a GeoSite database from a JSON file.
    ///
    /// Expected JSON format:
    /// ```json
    /// [
    ///   {"code": "cn", "domains": ["baidu.com", "weibo.com"]},
    ///   {"code": "google", "domains": ["google.com", "youtube.com"]}
    /// ]
    /// ```
    public init(filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GeoSiteError.invalidFile("file does not exist: \(filePath)")
        }

        let data = try Data(contentsOf: url)
        let sites = try JSONDecoder().decode([SiteEntry].self, from: data)

        var mapping: [String: Set<String>] = [:]
        for site in sites {
            for domain in site.domains {
                let normalized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                mapping[normalized, default: []].insert(site.code.lowercased())
            }
        }

        self.domainToCodes = mapping
    }

    // MARK: - Public

    /// Look up the site codes for a domain.
    /// - Parameter domain: The domain to look up.
    /// - Returns: Set of site codes, or nil if not found.
    public func lookupCodes(forDomain domain: String) -> Set<String>? {
        let normalized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return domainToCodes[normalized]
    }

    /// Check if a domain belongs to a specific site category.
    /// - Parameters:
    ///   - domain: The domain to check.
    ///   - code: The site code to check against.
    /// - Returns: true if the domain is categorized under the given code.
    public func matches(domain: String, code: String) -> Bool {
        guard let codes = lookupCodes(forDomain: domain) else { return false }
        return codes.contains(code.lowercased())
    }

    /// Check if a domain or any of its suffixes matches a site category.
    /// For example, `mail.google.com` should match `google.com`'s categories.
    public func matchesWithSuffix(domain: String, code: String) -> Bool {
        var current = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while !current.isEmpty {
            if matches(domain: current, code: code) {
                return true
            }
            // Strip the leftmost label
            if let dotIndex = current.firstIndex(of: ".") {
                current = String(current[current.index(after: dotIndex)...])
            } else {
                break
            }
        }
        return false
    }
}

// MARK: - ASN Resolver

/// Resolves IP addresses to Autonomous System Numbers (ASNs).
///
/// Used for IP-ASN rule matching: `IP-ASN,13335,PROXY` matches Cloudflare IPs.
///
/// This implementation uses a simple CIDR→ASN mapping loaded from a JSON file.
/// A full implementation would use the MaxMind or IP2ASN database.
public struct ASNResolver: Sendable {

    // MARK: - Errors

    public enum ASNError: Error, Equatable, Sendable {
        case invalidFile(String)
        case parseError(String)

        public var localizedDescription: String {
            switch self {
            case .invalidFile(let msg): return "Invalid ASN file: \(msg)"
            case .parseError(let msg): return "ASN parse error: \(msg)"
            }
        }
    }

    // MARK: - Data Model

    private struct ASNEntry: Codable {
        let cidr: String
        let asn: Int
    }

    // MARK: - State

    /// Parsed CIDR→ASN entries.
    private let entries: [(network: IPv4CIDR, asn: Int)]

    // MARK: - Init

    /// Load an ASN database from a JSON file.
    ///
    /// Expected JSON format:
    /// ```json
    /// [
    ///   {"cidr": "1.1.1.0/24", "asn": 13335},
    ///   {"cidr": "8.8.8.0/24", "asn": 15169}
    /// ]
    /// ```
    public init(filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ASNError.invalidFile("file does not exist: \(filePath)")
        }

        let data = try Data(contentsOf: url)
        let rawEntries = try JSONDecoder().decode([ASNEntry].self, from: data)

        var parsed: [(IPv4CIDR, Int)] = []
        for entry in rawEntries {
            if let cidr = IPv4CIDR(entry.cidr) {
                parsed.append((cidr, entry.asn))
            }
        }

        self.entries = parsed
    }

    // MARK: - Public

    /// Look up the ASN for an IP address.
    /// - Parameter ipAddress: IPv4 address.
    /// - Returns: ASN number, or nil if not found.
    public func lookupASN(forIP ipAddress: String) -> Int? {
        guard let ipValue = IPv4AddressParser.parse(ipAddress) else { return nil }
        for (network, asn) in entries {
            if network.contains(ipValue) {
                return asn
            }
        }
        return nil
    }

    /// Check if an IP belongs to a specific ASN.
    public func matches(ip: String, asn: Int) -> Bool {
        lookupASN(forIP: ip) == asn
    }

    /// Return the number of loaded entries.
    public var entryCount: Int {
        entries.count
    }
}
