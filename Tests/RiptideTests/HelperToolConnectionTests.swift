import XCTest
@testable import Riptide

/// Tests for HelperToolConnection — covers error types and state queries.
/// XPC integration tests require the helper tool to be installed and are
/// validated via manual smoke tests or CI with a privileged environment.
final class HelperToolConnectionTests: XCTestCase {

    // MARK: - ConnectionError

    func testConnectionErrorEquatable() {
        XCTAssertEqual(
            HelperToolConnection.ConnectionError.notInstalled,
            HelperToolConnection.ConnectionError.notInstalled
        )
        XCTAssertEqual(
            HelperToolConnection.ConnectionError.connectionFailed("timeout"),
            HelperToolConnection.ConnectionError.connectionFailed("timeout")
        )
        XCTAssertEqual(
            HelperToolConnection.ConnectionError.requestFailed("no response"),
            HelperToolConnection.ConnectionError.requestFailed("no response")
        )
        XCTAssertEqual(
            HelperToolConnection.ConnectionError.timedOut("launch"),
            HelperToolConnection.ConnectionError.timedOut("launch")
        )
        XCTAssertEqual(
            HelperToolConnection.ConnectionError.versionMismatch(hostVersion: "1.0", helperVersion: "0.9"),
            HelperToolConnection.ConnectionError.versionMismatch(hostVersion: "1.0", helperVersion: "0.9")
        )

        XCTAssertNotEqual(
            HelperToolConnection.ConnectionError.notInstalled,
            HelperToolConnection.ConnectionError.connectionFailed("x")
        )
        XCTAssertNotEqual(
            HelperToolConnection.ConnectionError.connectionFailed("a"),
            HelperToolConnection.ConnectionError.connectionFailed("b")
        )
        XCTAssertNotEqual(
            HelperToolConnection.ConnectionError.versionMismatch(hostVersion: "1.0", helperVersion: "0.9"),
            HelperToolConnection.ConnectionError.versionMismatch(hostVersion: "2.0", helperVersion: "0.9")
        )
    }

    func testConnectionErrorLocalizedDescription() {
        let cases: [HelperToolConnection.ConnectionError] = [
            .notInstalled,
            .connectionFailed("test"),
            .requestFailed("test"),
            .versionMismatch(hostVersion: "1.0", helperVersion: "0.9"),
            .timedOut("test-op"),
        ]

        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                "Expected non-empty localizedDescription for \(error)")
        }
    }

    // MARK: - HelperToolError

    func testHelperToolErrorLocalizedDescription() {
        let cases: [HelperToolError] = [
            .invalidConfigPath,
            .invalidBinaryPath,
            .pathNotInWhitelist,
            .mihomoAlreadyRunning,
            .mihomoNotRunning,
            .processLaunchFailed("test"),
            .processTerminationFailed("test"),
            .installationFailed("test"),
            .invalidMode("bad"),
            .encodingFailed,
        ]

        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                "Expected non-empty description for \(error)")
        }
    }

    // MARK: - RiptideError XPC Wrappers

    func testRiptideErrorXPCWrapping() {
        let helperError = HelperToolError.mihomoNotRunning
        let xpcError = RiptideError.xpc(helperError)
        XCTAssertNotNil(xpcError.localizedDescription)

        let connError = HelperToolConnection.ConnectionError.notInstalled
        let xpcConnError = RiptideError.xpcConnection(connError)
        XCTAssertNotNil(xpcConnError.localizedDescription)
    }
}
