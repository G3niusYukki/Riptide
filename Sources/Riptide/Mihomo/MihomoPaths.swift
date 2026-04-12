import Foundation

/// Provides file system paths for mihomo core integration.
/// All paths are relative to ~/Library/Application Support/Riptide/mihomo
public struct MihomoPaths: Sendable {

    /// Base directory: ~/Library/Application Support/Riptide/mihomo
    public let baseDirectory: URL

    /// The main mihomo executable path.
    public var executable: String {
        baseDirectory.appendingPathComponent("mihomo").path
    }

    /// Config directory (same as base): ~/Library/Application Support/Riptide/mihomo
    public var configDirectory: URL {
        baseDirectory
    }

    /// Config file: {base}/config.yaml
    public var configFileURL: URL {
        baseDirectory.appendingPathComponent("config.yaml")
    }

    /// Config backup: {base}/config.yaml.bak
    public var configBackupURL: URL {
        baseDirectory.appendingPathComponent("config.yaml.bak")
    }

    /// Cache directory: {base}/cache
    public var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    /// Log file: {base}/logs/mihomo.log
    public var logFileURL: URL {
        baseDirectory.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("mihomo.log")
    }

    /// GeoIP database: {cache}/GeoIP.dat
    public var geoIPDatURL: URL {
        cacheDirectory.appendingPathComponent("GeoIP.dat")
    }

    /// GeoSite database: {cache}/GeoSite.dat
    public var geoSiteDatURL: URL {
        cacheDirectory.appendingPathComponent("GeoSite.dat")
    }

    /// Creates a new MihomoPaths instance with the default base directory.
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseDirectory = appSupport
            .appendingPathComponent("Riptide", isDirectory: true)
            .appendingPathComponent("mihomo", isDirectory: true)
    }

    /// Creates all necessary directories with intermediate directories.
    /// - Throws: FileManager errors if directory creation fails.
    public func createDirectories() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}
