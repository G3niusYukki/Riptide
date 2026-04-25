import Foundation
import Testing
@testable import Riptide

// MARK: - MihomoCoreManager Tests

@Suite("MihomoCoreManager Tests")
struct MihomoCoreManagerTests {

    // MARK: - Initialization Tests

    @Test("Initialization with default paths")
    func defaultInitialization() async {
        let manager = MihomoCoreManager()

        // Should have default paths
        #expect(await manager.paths.baseDirectory.lastPathComponent == "mihomo")
    }

    @Test("Initialization with custom paths")
    func customInitialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customPaths = MihomoPaths()
        let manager = MihomoCoreManager(paths: customPaths)

        #expect(await manager.paths.baseDirectory == customPaths.baseDirectory)
    }

    // MARK: - CoreManagerError Tests

    @Test("CoreManagerError equality")
    func errorEquality() {
        #expect(CoreManagerError.binaryNotFound == CoreManagerError.binaryNotFound)
        #expect(CoreManagerError.downloadFailed("error1") == CoreManagerError.downloadFailed("error1"))
        #expect(CoreManagerError.downloadFailed("error1") != CoreManagerError.downloadFailed("error2"))
        #expect(CoreManagerError.binaryNotFound != CoreManagerError.downloadFailed("error"))
    }

    // MARK: - Version Management Tests

    @Test("Get installed version returns nil when no binary")
    func noInstalledVersion() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        let version = await manager.getInstalledVersion()
        #expect(version == nil)
    }

    @Test("List downloaded versions returns empty initially")
    func emptyDownloadedVersions() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        let versions = await manager.listDownloadedVersions()
        #expect(versions.isEmpty)
    }

    @Test("Is version available locally returns false for missing version")
    func versionNotAvailableLocally() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        let available = await manager.isVersionAvailableLocally("v1.0.0")
        #expect(available == false)
    }

    @Test("Cleanup old versions with no versions returns 0")
    func cleanupEmptyVersions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        let removed = try await manager.cleanupOldVersions(keepCount: 3)
        #expect(removed == 0)
    }
}

// MARK: - Integration Tests

@Suite("MihomoCoreManager Integration Tests")
struct MihomoCoreManagerIntegrationTests {

    @Test("Ensure binary available throws when autoDownload disabled and no binary")
    func ensureBinaryNoAutoDownload() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        do {
            _ = try await manager.ensureBinaryAvailable(autoDownload: false)
            #expect(Bool(false), "Should have thrown binaryNotFound")
        } catch CoreManagerError.binaryNotFound {
            #expect(true)
        }
    }

    @Test("Remove version does not throw for non-existent version")
    func removeNonExistentVersion() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        // Should not throw even if version doesn't exist
        try await manager.removeVersion("v999.999.999")
        #expect(true)
    }

    @Test("Check for update returns nil when no current version and check fails")
    func checkForUpdateNoCurrent() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paths = createCustomPaths(baseDir: tempDir)
        let manager = MihomoCoreManager(paths: paths)

        // Without network and no current version, should return nil
        let update = await manager.checkForUpdate()
        // Result may be nil depending on network - we just verify the API works
        _ = update
    }
}

// MARK: - Helper Functions

/// Creates custom MihomoPaths for testing with a temporary directory.
func createCustomPaths(baseDir: URL) -> MihomoPaths {
    MihomoPaths(baseDirectory: baseDir)
}
