import Foundation

// MARK: - Entry

public enum LogbookEntry: Codable, Equatable, Sendable {
    case event(LogEvent)
    case connectionClosed(ClosedConnectionRecord)
}

// MARK: - Category

public enum LogbookCategory: String, Codable, Sendable, CaseIterable {
    case modeChange
    case subscription
    case profileSwitch
    case helperInstall
    case mihomoCore
    case override
    case rule
    case dns
    case diagnostic
    case appLifecycle
}

// MARK: - LogEvent

public struct LogEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogbookCategory
    public let message: String
    public let context: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogbookCategory,
        message: String,
        context: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.context = context
    }
}

// MARK: - ClosedConnectionRecord

public enum CloseReason: String, Codable, Sendable {
    case userClosed
    case userClosedAll
    case expired
    case idleTimeout
    case error
    case mihomoRestart
}

public struct ClosedConnectionRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let host: String
    public let proxyName: String
    public let `protocol`: String
    public let rule: String?
    public let sourceIP: String
    public let sourcePort: Int?
    public let destinationIP: String?
    public let destinationPort: Int?
    public let startedAt: Date
    public let closedAt: Date
    public let uploadBytes: Int
    public let downloadBytes: Int
    public let closeReason: CloseReason

    public init(
        id: String,
        host: String,
        proxyName: String,
        protocol: String,
        rule: String?,
        sourceIP: String,
        sourcePort: Int?,
        destinationIP: String?,
        destinationPort: Int?,
        startedAt: Date,
        closedAt: Date,
        uploadBytes: Int,
        downloadBytes: Int,
        closeReason: CloseReason
    ) {
        self.id = id
        self.host = host
        self.proxyName = proxyName
        self.protocol = `protocol`
        self.rule = rule
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.startedAt = startedAt
        self.closedAt = closedAt
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.closeReason = closeReason
    }
}

// MARK: - Query

public struct LogbookQuery: Sendable, Equatable {
    public var from: Date
    public var to: Date
    public var levels: Set<LogLevel>
    public var categories: Set<LogbookCategory>
    public var hostContains: String?
    public var proxyName: String?
    public var limit: Int

    public init(
        from: Date,
        to: Date,
        levels: Set<LogLevel> = [],
        categories: Set<LogbookCategory> = [],
        hostContains: String? = nil,
        proxyName: String? = nil,
        limit: Int = 1000
    ) {
        self.from = from
        self.to = to
        self.levels = levels
        self.categories = categories
        self.hostContains = hostContains
        self.proxyName = proxyName
        self.limit = min(limit, 5000)
    }

    public static func last24h(limit: Int = 1000) -> LogbookQuery {
        let now = Date()
        return LogbookQuery(
            from: now.addingTimeInterval(-24 * 3600),
            to: now,
            limit: limit
        )
    }

    public static func last7d(limit: Int = 1000) -> LogbookQuery {
        let now = Date()
        return LogbookQuery(
            from: now.addingTimeInterval(-7 * 24 * 3600),
            to: now,
            limit: limit
        )
    }
}

// MARK: - ISO 8601 codec

extension JSONEncoder {
    public static let iso8601: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, enc2 in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = enc2.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return enc
    }()
}

extension JSONDecoder {
    public static let iso8601: JSONDecoder = {
        let dec = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dec.dateDecodingStrategy = .custom { dec2 in
            let container = try dec2.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) { return date }
            // Fallback for timestamps without fractional seconds
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO 8601 date: \(raw)"
            )
        }
        return dec
    }()
}
