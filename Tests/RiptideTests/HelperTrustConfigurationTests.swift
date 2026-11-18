import Foundation
import XCTest
@testable import Riptide

/// Pins the shipped helper trust configuration so a placeholder Team ID or
/// a stale client bundle ID cannot silently return (ADR-0004 / ADR-0012).
final class HelperTrustConfigurationTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/RiptideTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
    }

    func test_shipped_audit_policy_uses_resolved_team_and_app_bundle_id() throws {
        let url = repositoryRoot.appendingPathComponent("RiptideHelper/Resources/audit-policy.plist")
        let data = try Data(contentsOf: url)
        let policy = try PropertyListDecoder().decode(CallerPolicy.self, from: data)

        XCTAssertFalse(policy.allowedTeamID.contains("YOUR_"))
        XCTAssertFalse(policy.allowedBundleID.contains("YOUR_"))
        XCTAssertEqual(policy.allowedTeamID, "39Q4M52XNQ")
        XCTAssertEqual(policy.allowedBundleID, "com.riptide.app")
    }

    func test_helper_info_plist_requirement_has_no_placeholder() throws {
        let url = repositoryRoot.appendingPathComponent("RiptideHelper/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let clients = try XCTUnwrap(
            (plist as? [String: Any])?["SMAuthorizedClients"] as? [String],
            "SMAuthorizedClients missing"
        )
        let requirement = clients.joined(separator: " ")

        XCTAssertFalse(requirement.contains("YOUR_TEAM_ID"))
        XCTAssertTrue(requirement.contains("39Q4M52XNQ"))
        XCTAssertTrue(requirement.contains("com.riptide.app"))
        XCTAssertFalse(requirement.contains("subject.CN"), "must not commit a personal CN")
    }
}
