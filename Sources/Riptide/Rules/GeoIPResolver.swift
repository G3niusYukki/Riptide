import Foundation

public struct GeoIPResolver: Sendable {
    public let resolveCountryCode: @Sendable (String) -> String?

    public init(resolveCountryCode: @escaping @Sendable (String) -> String?) {
        self.resolveCountryCode = resolveCountryCode
    }

    /// Create a GeoIPResolver backed by an MMDB database.
    public init(database: GeoIPDatabase) {
        self.resolveCountryCode = { ip in
            database.lookupCountryCode(forIP: ip)
        }
    }

    /// Create a resolver that always returns nil (no GeoIP data).
    public static let none = GeoIPResolver { _ in nil }
}
