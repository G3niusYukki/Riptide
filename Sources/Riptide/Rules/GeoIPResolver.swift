import Foundation

public struct GeoIPResolver: Sendable {
    public let resolveCountryCode: @Sendable (String) -> String?

    public init(resolveCountryCode: @escaping @Sendable (String) -> String?) {
        self.resolveCountryCode = resolveCountryCode
    }

    public static let none = GeoIPResolver { _ in nil }
}
