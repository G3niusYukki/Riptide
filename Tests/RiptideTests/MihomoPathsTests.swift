import XCTest
@testable import Riptide

@available(macOS 14.0, *)
final class MihomoPathsTests: XCTestCase {
    func testConfigDirectory() {
        let paths = MihomoPaths()
        let path = paths.configDirectory.path
        XCTAssertTrue(path.contains("Application Support/Riptide/mihomo"), "Config directory should contain 'Application Support/Riptide/mihomo'")
    }

    func testConfigFileURL() {
        let paths = MihomoPaths()
        let lastComponent = paths.configFileURL.lastPathComponent
        XCTAssertEqual(lastComponent, "config.yaml", "Config file should be named 'config.yaml'")
    }

    func testCacheDirectory() {
        let paths = MihomoPaths()
        let lastComponent = paths.cacheDirectory.lastPathComponent
        XCTAssertEqual(lastComponent, "cache", "Cache directory should be named 'cache'")
    }

    func testLogFileURL() {
        let paths = MihomoPaths()
        let lastComponent = paths.logFileURL.lastPathComponent
        XCTAssertEqual(lastComponent, "mihomo.log", "Log file should be named 'mihomo.log'")
    }
}
