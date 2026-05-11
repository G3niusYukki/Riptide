import XCTest
@testable import Riptide

/// Tests for WebDAV sync types: error conformance and file model.
final class WebDAVClientTests: XCTestCase {

    // MARK: - WebDAVError Equatable

    func testWebDAVErrorEquatable() {
        XCTAssertEqual(WebDAVError.notConfigured, WebDAVError.notConfigured)
        XCTAssertEqual(WebDAVError.invalidURL, WebDAVError.invalidURL)
        XCTAssertEqual(WebDAVError.invalidCredentials, WebDAVError.invalidCredentials)
        XCTAssertEqual(WebDAVError.notFound, WebDAVError.notFound)
        XCTAssertEqual(WebDAVError.syncInProgress, WebDAVError.syncInProgress)
        XCTAssertEqual(WebDAVError.conflictResolutionFailed, WebDAVError.conflictResolutionFailed)

        XCTAssertEqual(WebDAVError.serverError(500, "err"), WebDAVError.serverError(500, "err"))
        XCTAssertNotEqual(WebDAVError.serverError(500, "a"), WebDAVError.serverError(500, "b"))
        XCTAssertNotEqual(WebDAVError.serverError(500, "x"), WebDAVError.serverError(502, "x"))

        XCTAssertEqual(WebDAVError.listFailed("a"), WebDAVError.listFailed("a"))
        XCTAssertNotEqual(WebDAVError.listFailed("a"), WebDAVError.listFailed("b"))

        XCTAssertNotEqual(WebDAVError.invalidURL, WebDAVError.notFound)
    }

    // MARK: - WebDAVError LocalizedError

    func testWebDAVErrorLocalizedDescription() {
        let cases: [WebDAVError] = [
            .notConfigured,
            .invalidURL,
            .invalidCredentials,
            .listFailed("timeout"),
            .downloadFailed("404"),
            .uploadFailed("perm denied"),
            .deleteFailed("locked"),
            .networkError("unreachable"),
            .parsingError("malformed XML"),
            .keychainError("access denied"),
            .syncInProgress,
            .conflictResolutionFailed,
            .serverError(502, "bad gateway"),
            .notFound,
        ]

        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                "Expected non-empty description for \(error)")
        }
    }

    // MARK: - WebDAVFile

    func testWebDAVFileInit() {
        let date = Date()
        let file = WebDAVFile(
            path: "/dav/configs/test.yaml",
            name: "test.yaml",
            size: 1024,
            modified: date,
            isDirectory: false,
            etag: "\"abc123\""
        )

        XCTAssertEqual(file.path, "/dav/configs/test.yaml")
        XCTAssertEqual(file.name, "test.yaml")
        XCTAssertEqual(file.size, 1024)
        XCTAssertEqual(file.modified, date)
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.etag, "\"abc123\"")
    }

    func testWebDAVFileDirectoryDefaults() {
        let file = WebDAVFile(path: "/dav/configs", name: "configs")

        XCTAssertEqual(file.path, "/dav/configs")
        XCTAssertEqual(file.name, "configs")
        XCTAssertEqual(file.size, 0)
        XCTAssertFalse(file.isDirectory)
        XCTAssertNil(file.etag)
    }

    func testWebDAVFileEquatable() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000000)
        let a = WebDAVFile(id: id, path: "/a", name: "a", modified: date)
        let b = WebDAVFile(id: id, path: "/a", name: "a", modified: date)
        let c = WebDAVFile(id: UUID(), path: "/b", name: "b", modified: date)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testWebDAVFileIdentifiable() {
        let file = WebDAVFile(path: "/test", name: "test")
        // Just verify id exists and is unique
        let file2 = WebDAVFile(path: "/test", name: "test")
        XCTAssertNotEqual(file.id, file2.id)
    }
}
