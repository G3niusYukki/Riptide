import Foundation

// MARK: - Subscription Userinfo

/// Parsed subscription quota information from the `subscription-userinfo` HTTP response header.
///
/// Standard header format (as used by Clash, Surge, etc.):
/// ```
/// subscription-userinfo: upload=1234; download=5678; total=100000; expire=1735689600
/// ```
///
/// All fields are optional since providers may omit any of them.
public struct SubscriptionUserinfo: Sendable, Equatable, Codable {
    /// Bytes uploaded in the current billing period.
    public let uploadBytes: Int64?
    /// Bytes downloaded in the current billing period.
    public let downloadBytes: Int64?
    /// Total bytes included in the subscription plan.
    public let totalBytes: Int64?
    /// Expiry timestamp as a Unix epoch second.
    public let expireTimestamp: Int64?

    public init(
        uploadBytes: Int64? = nil,
        downloadBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        expireTimestamp: Int64? = nil
    ) {
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.totalBytes = totalBytes
        self.expireTimestamp = expireTimestamp
    }

    /// The expiry date derived from the Unix timestamp, or nil.
    public var expireDate: Date? {
        guard let ts = expireTimestamp, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Combined bytes used (upload + download), or nil if either is missing.
    public var usedBytes: Int64? {
        guard let up = uploadBytes, let down = downloadBytes else { return nil }
        return up + down
    }

    /// Usage ratio [0..1], nil when total is unavailable or zero.
    public var usageRatio: Double? {
        guard let used = usedBytes, let total = totalBytes, total > 0 else { return nil }
        let ratio = Double(used) / Double(total)
        return min(max(ratio, 0), 1)
    }

    /// Returns true when the subscription is within 72 hours of expiry.
    public var isExpiringSoon: Bool {
        guard let date = expireDate else { return false }
        let threshold = Date().addingTimeInterval(72 * 3600)
        return date <= threshold
    }

    /// Returns true when the subscription has already expired.
    public var isExpired: Bool {
        guard let date = expireDate else { return false }
        return date <= Date()
    }

    /// Whether there's any meaningful data in this instance.
    public var isEmpty: Bool {
        uploadBytes == nil && downloadBytes == nil && totalBytes == nil && expireTimestamp == nil
    }
}

// MARK: - Parser

/// Parses the `subscription-userinfo` HTTP response header.
public enum SubscriptionUserinfoParser {

    /// Parses the value of a `subscription-userinfo` header string.
    ///
    /// Format: `key1=value1; key2=value2; ...`
    ///
    /// Supported keys:
    /// - `upload` — bytes uploaded (Int64)
    /// - `download` — bytes downloaded (Int64)
    /// - `total` — total bytes included (Int64)
    /// - `expire` — Unix timestamp of expiry (Int64)
    ///
    /// - Parameter headerValue: The raw header value string.
    /// - Returns: A populated `SubscriptionUserinfo`, or an empty one if parsing yields nothing.
    public static func parse(_ headerValue: String) -> SubscriptionUserinfo {
        var upload: Int64?
        var download: Int64?
        var total: Int64?
        var expire: Int64?

        let segments = headerValue.split(separator: ";")
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let valueStr = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "upload":
                upload = Int64(valueStr)
            case "download":
                download = Int64(valueStr)
            case "total":
                total = Int64(valueStr)
            case "expire":
                expire = Int64(valueStr)
            default:
                break
            }
        }

        return SubscriptionUserinfo(
            uploadBytes: upload,
            downloadBytes: download,
            totalBytes: total,
            expireTimestamp: expire
        )
    }

    /// Extracts and parses the `subscription-userinfo` header from an HTTPURLResponse.
    ///
    /// - Parameter response: The HTTP response to inspect.
    /// - Returns: A populated `SubscriptionUserinfo`, or nil if the header is absent or empty.
    public static func extract(from response: HTTPURLResponse) -> SubscriptionUserinfo? {
        guard let headerValue = response.value(forHTTPHeaderField: "subscription-userinfo"),
              !headerValue.isEmpty else {
            return nil
        }
        let info = parse(headerValue)
        return info.isEmpty ? nil : info
    }
}
