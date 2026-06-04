import XCTest
@testable import Riptide

final class HelperEndpointTestHarnessTests: XCTestCase {
    /// Simulates the "foreign caller" attack pattern: a process with
    /// a different bundle identifier attempting to talk to the helper.
    /// The harness must reject the connection based on caller policy.
    func test_harness_rejects_foreign_caller() {
        let policy = CallerPolicy(allowedTeamID: "ABCDE12345", allowedBundleID: "com.riptide.client")
        let validator = HelperCallerValidator(policy: policy)
        let harness = HelperEndpointTestHarness(validator: validator)

        let foreignToken = CallerAuditToken(
            teamID: "EVIL99999",
            bundleID: "com.evil.app"
        )

        let result = harness.simulateIncomingConnection(
            callerToken: foreignToken,
            callerRequirement: "identifier \"com.evil.app\""
        )

        XCTAssertFalse(result.accepted, "Foreign caller must be rejected")
        XCTAssertEqual(result.rejectionReason, .teamIDMismatch)
    }

    /// The legitimate Riptide app path: bundle ID matches and team ID matches.
    func test_harness_accepts_legitimate_caller() {
        let policy = CallerPolicy(allowedTeamID: "ABCDE12345", allowedBundleID: "com.riptide.client")
        let validator = HelperCallerValidator(policy: policy)
        let harness = HelperEndpointTestHarness(validator: validator)

        let legitToken = CallerAuditToken(
            teamID: "ABCDE12345",
            bundleID: "com.riptide.client"
        )

        let result = harness.simulateIncomingConnection(
            callerToken: legitToken,
            callerRequirement: "identifier \"com.riptide.client\""
        )

        XCTAssertTrue(result.accepted, "Legitimate caller must be accepted")
        XCTAssertNil(result.rejectionReason)
    }
}
