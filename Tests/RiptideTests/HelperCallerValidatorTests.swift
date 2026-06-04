import XCTest
@testable import Riptide

final class HelperCallerValidatorTests: XCTestCase {
    func test_validator_rejects_caller_when_audit_token_missing() {
        // Arrange
        let policy = CallerPolicy(allowedTeamID: "ABCDE12345", allowedBundleID: "com.riptide.client")
        let validator = HelperCallerValidator(policy: policy)

        // Act
        let result = validator.validate(auditToken: nil, codeSigningRequirement: nil)

        // Assert
        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.reason, .missingAuditToken)
    }

    func test_validator_rejects_caller_when_bundle_id_mismatches() {
        // Arrange
        let policy = CallerPolicy(allowedTeamID: "ABCDE12345", allowedBundleID: "com.riptide.client")
        let validator = HelperCallerValidator(policy: policy)

        // Act
        let result = validator.validate(
            auditToken: AuditTokenFixture.unprivileged(),
            codeSigningRequirement: "identifier \"com.evil.app\""
        )

        // Assert
        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.reason, .bundleIDMismatch)
    }

    func test_validator_accepts_caller_when_bundle_id_matches_and_team_id_present() {
        // Arrange
        let policy = CallerPolicy(allowedTeamID: "ABCDE12345", allowedBundleID: "com.riptide.client")
        let validator = HelperCallerValidator(policy: policy)

        // Act
        let result = validator.validate(
            auditToken: AuditTokenFixture.privileged(teamID: "ABCDE12345"),
            codeSigningRequirement: "identifier \"com.riptide.client\""
        )

        // Assert
        XCTAssertTrue(result.isAllowed)
        XCTAssertNil(result.reason)
    }
}

// MARK: - Fixtures

enum AuditTokenFixture {
    /// Returns a non-nil placeholder; real audit tokens come from SecCodeCopySelf
    /// in production. Tests use a thin abstraction so the validator logic is
    /// testable without a live XPC connection.
    static func unprivileged() -> CallerAuditToken {
        CallerAuditToken(teamID: "ABCDE12345", bundleID: "com.unknown.app")
    }
    static func privileged(teamID: String) -> CallerAuditToken {
        CallerAuditToken(teamID: teamID, bundleID: "com.riptide.client")
    }
}
