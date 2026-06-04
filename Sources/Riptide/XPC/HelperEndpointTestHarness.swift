import Foundation

/// A test-side simulator of the helper's XPC listener.
///
/// `HelperEndpointTestHarness` exists so the LPE-replay attack pattern
/// (unsigned / foreign caller connecting to the helper endpoint) can be
/// asserted in CI without spinning up a real XPC service. The harness
/// wires the same `HelperCallerValidator` the production helper uses.
public struct HelperEndpointTestHarness: Sendable {
    public struct IncomingResult: Equatable, Sendable {
        public let accepted: Bool
        public let rejectionReason: CallerRejectionReason?
    }

    public let validator: HelperCallerValidator

    public init(validator: HelperCallerValidator) {
        self.validator = validator
    }

    /// Simulates the helper's `shouldAcceptNewConnection` decision
    /// for a given caller token + requirement. Mirrors
    /// `RiptideHelper/Sources/HelperTool.swift:listener(_:shouldAcceptNewConnection:)`
    /// without invoking real SecCode APIs.
    public func simulateIncomingConnection(
        callerToken: CallerAuditToken?,
        callerRequirement: String?
    ) -> IncomingResult {
        let result = validator.validate(
            auditToken: callerToken,
            codeSigningRequirement: callerRequirement
        )
        return IncomingResult(
            accepted: result.isAllowed,
            rejectionReason: result.reason
        )
    }
}
