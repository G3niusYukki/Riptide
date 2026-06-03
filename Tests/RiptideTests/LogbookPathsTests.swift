import Foundation
import Testing

@testable import Riptide

@Suite("Logbook paths")
struct LogbookPathsTests {

    @Test("default directory resolves under Application Support")
    func defaultDirectoryIsUnderAppSupport() {
        let paths = LogbookPaths.default
        #expect(paths.directory.lastPathComponent == "logbook")
        let expectedRoot = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Riptide", isDirectory: true)
        #expect(paths.directory.path.hasPrefix(expectedRoot.path))
    }

    @Test("directory creation is idempotent")
    func createIfNeededIsIdempotent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-paths-test-\(UUID().uuidString)")
        let paths = LogbookPaths(directory: tmp)
        try paths.createDirectoryIfNeeded()
        try paths.createDirectoryIfNeeded()  // must not throw on second call
        #expect(FileManager.default.fileExists(atPath: tmp.path))
        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("file URL uses UTC date")
    func fileURLUsesUTCDate() {
        let paths = LogbookPaths.default
        let date = Date(timeIntervalSince1970: 1_748_928_000)  // 2025-06-03 00:00:00 UTC
        let url = paths.fileURL(for: date)
        #expect(url.lastPathComponent == "2025-06-03.jsonl")
    }
}
