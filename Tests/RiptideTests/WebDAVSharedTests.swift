import Foundation
import Testing
@testable import Riptide

/// FIX-5: shared path-resolution helper for the project's WebDAV clients.
@Suite("WebDAVShared")
struct WebDAVSharedTests {

    @Test("resolveURL returns baseURL for empty path")
    func resolveURLEmptyPath() {
        let base = URL(string: "https://dav.example.com/")!
        let result = WebDAVShared.resolveURL(baseURL: base, for: "")
        #expect(result == base)
    }

    @Test("resolveURL strips leading slashes from path")
    func resolveURLStripsLeadingSlashes() {
        let base = URL(string: "https://dav.example.com/")!
        let result = WebDAVShared.resolveURL(baseURL: base, for: "/backups/file.json")
        #expect(result?.path == "/backups/file.json")
    }

    @Test("resolveURL appends trailing slash to base when missing")
    func resolveURLAppendsTrailingSlashToBase() {
        let base = URL(string: "https://dav.example.com")! // no trailing slash
        let result = WebDAVShared.resolveURL(baseURL: base, for: "file.json")
        #expect(result?.path == "/file.json")
    }

    @Test("propfindBody is non-empty and contains D:propfind")
    func propfindBodyLooksValid() {
        let body = String(data: WebDAVShared.propfindBody, encoding: .utf8) ?? ""
        #expect(!body.isEmpty)
        #expect(body.contains("D:propfind"))
        #expect(body.contains("D:displayname"))
        #expect(body.contains("D:getcontentlength"))
        #expect(body.contains("D:getlastmodified"))
        #expect(body.contains("D:resourcetype"))
    }
}
