import Foundation

/// Severity level of validation issues
public enum ValidationSeverity: Sendable, Comparable {
    case info
    case warning
    case error
}

/// A single validation issue
public struct ValidationIssue: Sendable, Identifiable {
    public let id = UUID()
    public let line: Int?
    public let column: Int?
    public let severity: ValidationSeverity
    public let message: String
    public let path: String
    public let suggestion: String?

    public init(
        line: Int? = nil,
        column: Int? = nil,
        severity: ValidationSeverity,
        message: String,
        path: String,
        suggestion: String? = nil
    ) {
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.path = path
        self.suggestion = suggestion
    }
}

/// Result of configuration validation
public struct ConfigValidationResult: Sendable {
    public let issues: [ValidationIssue]
    public let isValid: Bool

    public var errors: [ValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [ValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    public var info: [ValidationIssue] {
        issues.filter { $0.severity == .info }
    }

    public init(issues: [ValidationIssue]) {
        self.issues = issues
        self.isValid = !issues.contains { $0.severity == .error }
    }
}
