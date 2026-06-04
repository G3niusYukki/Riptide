import Foundation

/// A thin abstraction over an audit token so validator logic is testable
/// without a live XPC connection. In production, `auditToken` is filled
/// from `SecCodeCopySelf()` on the helper side; `codeSigningRequirement`
/// comes from `SecCodeCopySigningInformation`.
public struct CallerAuditToken: Equatable, Sendable {
    public let teamID: String?
    public let bundleID: String?
    public init(teamID: String?, bundleID: String?) {
        self.teamID = teamID
        self.bundleID = bundleID
    }
}

public struct CallerPolicy: Equatable, Sendable, Codable {
    public let allowedTeamID: String
    public let allowedBundleID: String
    public init(allowedTeamID: String, allowedBundleID: String) {
        self.allowedTeamID = allowedTeamID
        self.allowedBundleID = allowedBundleID
    }
}

public enum CallerRejectionReason: Equatable, Sendable {
    case missingAuditToken
    case missingCodeSigningRequirement
    case teamIDMismatch
    case bundleIDMismatch
}

public struct CallerValidationResult: Equatable, Sendable {
    public let isAllowed: Bool
    public let reason: CallerRejectionReason?
    public init(isAllowed: Bool, reason: CallerRejectionReason? = nil) {
        self.isAllowed = isAllowed
        self.reason = reason
    }
}

public struct HelperCallerValidator: Sendable {
    public let policy: CallerPolicy
    public init(policy: CallerPolicy) {
        self.policy = policy
    }

    public func validate(
        auditToken: CallerAuditToken?,
        codeSigningRequirement: String?
    ) -> CallerValidationResult {
        guard let token = auditToken else {
            return CallerValidationResult(isAllowed: false, reason: .missingAuditToken)
        }
        guard codeSigningRequirement != nil else {
            return CallerValidationResult(isAllowed: false, reason: .missingCodeSigningRequirement)
        }
        if token.teamID != policy.allowedTeamID {
            return CallerValidationResult(isAllowed: false, reason: .teamIDMismatch)
        }
        if token.bundleID != policy.allowedBundleID {
            return CallerValidationResult(isAllowed: false, reason: .bundleIDMismatch)
        }
        return CallerValidationResult(isAllowed: true)
    }
}
