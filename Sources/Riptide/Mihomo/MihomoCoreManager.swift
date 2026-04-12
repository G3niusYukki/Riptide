import Foundation

// MARK: - Core Manager Errors

/// Errors that can occur during mihomo core management.
public enum CoreManagerError: Error, Equatable, Sendable {
    /// Download failed.
    case downloadFailed(String)
    /// Binary not found after download.
    case binaryNotFound
    /// Failed to set up binary path.
    case setupFailed(String)
}

// MARK: - Mihomo Core Manager

/// Manages the mihomo core binary lifecycle including automatic downloads.
/// Coordinates between the downloader and runtime to ensure the binary is always available.
public actor MihomoCoreManager {

    // MARK: - Properties

    /// Paths for mihomo file system layout.
    public let paths: MihomoPaths

    /// The downloader for fetching mihomo binaries.
    private let downloader: MihomoDownloader

    /// Currently installed version (cached).
    private var installedVersion: String?

    // MARK: - Initialization

    /// Creates a new MihomoCoreManager with the specified paths and downloader.
    /// - Parameters:
    ///   - paths: The paths instance for file system operations. Defaults to standard paths.
    ///   - downloader: The downloader instance. Defaults to a new MihomoDownloader.
    public init(
        paths: MihomoPaths = MihomoPaths(),
        downloader: MihomoDownloader? = nil
    ) {
        self.paths = paths
        self.downloader = downloader ?? MihomoDownloader(
            downloadDir: paths.baseDirectory.appendingPathComponent("bin", isDirectory: true)
        )
    }

    // MARK: - Public API

    /// Ensures the mihomo binary is available at the expected path.
    /// - Parameters:
    ///   - requiredVersion: Specific version to install, or nil for latest stable.
    ///   - autoDownload: Whether to automatically download if not found. Defaults to true.
    /// - Returns: The path to the mihomo binary.
    /// - Throws: CoreManagerError if the binary cannot be made available.
    public func ensureBinaryAvailable(
        version requiredVersion: String? = nil,
        autoDownload: Bool = true
    ) async throws -> String {
        // 1. Check if binary already exists at the expected path
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.executable) {
            // Verify it's executable
            if isExecutable(at: paths.executable) {
                // Update installed version cache
                installedVersion = getCurrentMihomoVersion(executablePath: paths.executable)
                return paths.executable
            }
        }

        // 2. If specific version requested, check if already downloaded
        if let version = requiredVersion {
            if let localPath = await downloader.pathForVersion(version) {
                try installBinary(from: localPath)
                installedVersion = version
                return paths.executable
            }
        }

        // 3. Check for any local version if no specific version requested
        if requiredVersion == nil {
            let localVersions = await downloader.listLocalVersions()
            if let latestLocal = localVersions.last {
                if let localPath = await downloader.pathForVersion(latestLocal) {
                    try installBinary(from: localPath)
                    installedVersion = latestLocal
                    return paths.executable
                }
            }
        }

        // 4. Auto-download if enabled
        guard autoDownload else {
            throw CoreManagerError.binaryNotFound
        }

        do {
            let downloadedPath: URL
            if let version = requiredVersion {
                downloadedPath = try await downloader.downloadVersion(version)
            } else {
                downloadedPath = try await downloader.downloadLatest(channel: .stable)
            }

            try installBinary(from: downloadedPath)
            installedVersion = requiredVersion ?? getCurrentMihomoVersion(executablePath: paths.executable)
            return paths.executable
        } catch let error as DownloadError {
            throw CoreManagerError.downloadFailed(String(describing: error))
        } catch {
            throw CoreManagerError.downloadFailed(error.localizedDescription)
        }
    }

    /// Checks if a specific version is available locally.
    /// - Parameter version: The version string (e.g., "v1.18.0" or "1.18.0").
    /// - Returns: True if the version is available locally.
    public func isVersionAvailableLocally(_ version: String) async -> Bool {
        return await downloader.pathForVersion(version) != nil
    }

    /// Gets the currently installed/active version.
    /// - Returns: The version string if available, nil otherwise.
    public func getInstalledVersion() -> String? {
        if let cached = installedVersion {
            return cached
        }

        // Check the actual binary
        let version = getCurrentMihomoVersion(executablePath: paths.executable)
        if version != "unknown" {
            installedVersion = version
            return version
        }
        return nil
    }

    /// Updates the mihomo binary to the latest version.
    /// - Parameter channel: The release channel (stable or alpha). Defaults to stable.
    /// - Returns: The new version string.
    /// - Throws: CoreManagerError if the update fails.
    public func updateToLatest(channel: MihomoDownloader.Channel = .stable) async throws -> String {
        do {
            let downloadedPath = try await downloader.downloadLatest(channel: channel)
            let newVersion = getCurrentMihomoVersion(executablePath: downloadedPath.path)
            try installBinary(from: downloadedPath)
            installedVersion = newVersion
            return newVersion
        } catch let error as DownloadError {
            throw CoreManagerError.downloadFailed(String(describing: error))
        } catch {
            throw CoreManagerError.downloadFailed(error.localizedDescription)
        }
    }

    /// Checks if an update is available.
    /// - Parameters:
    ///   - channel: The release channel to check. Defaults to stable.
    ///   - includePrerelease: Whether to include prerelease versions. Defaults to false.
    /// - Returns: UpdateInfo if an update is available, nil if up to date or on error.
    public func checkForUpdate(
        channel: MihomoDownloader.Channel = .stable
    ) async -> MihomoDownloader.UpdateInfo? {
        guard let currentVersion = getInstalledVersion() else {
            // If no current version, any version is an update
            let release = await downloader.checkForUpdate(currentVersion: "0.0.0", channel: channel)
            return release
        }

        return await downloader.checkForUpdate(currentVersion: currentVersion, channel: channel)
    }

    /// Lists all downloaded versions.
    /// - Returns: Array of version strings.
    public func listDownloadedVersions() -> [String] {
        return downloader.listLocalVersions()
    }

    /// Removes a specific downloaded version.
    /// - Parameter version: The version to remove.
    /// - Throws: FileManager errors if removal fails.
    public func removeVersion(_ version: String) throws {
        let fm = FileManager.default
        let normalizedVersion = version.hasPrefix("v") ? version : "v\(version)"
        let versionDir = downloader.downloadDir
            .appendingPathComponent("mihomo-\(normalizedVersion)")

        if fm.fileExists(atPath: versionDir.path) {
            try fm.removeItem(at: versionDir)
        }

        // If this was the installed version, clear the cache
        if installedVersion == normalizedVersion || installedVersion == version {
            installedVersion = nil
        }
    }

    /// Cleans up old versions, keeping only the specified number of recent versions.
    /// - Parameter keepCount: Number of versions to keep. Defaults to 3.
    /// - Returns: Number of versions removed.
    /// - Throws: FileManager errors if cleanup fails.
    @discardableResult
    public func cleanupOldVersions(keepCount: Int = 3) throws -> Int {
        let versions = downloader.listLocalVersions()
        guard versions.count > keepCount else { return 0 }

        let versionsToRemove = versions.dropLast(keepCount)
        var removedCount = 0

        for version in versionsToRemove {
            do {
                try removeVersion(version)
                removedCount += 1
            } catch {
                // Continue with other versions even if one fails
            }
        }

        return removedCount
    }

    // MARK: - Private Methods

    /// Installs a downloaded binary to the active location.
    /// - Parameter sourcePath: Path to the downloaded binary.
    /// - Throws: CoreManagerError if installation fails.
    private func installBinary(from sourcePath: URL) throws {
        let fm = FileManager.default
        let destinationPath = URL(fileURLWithPath: paths.executable)

        // Create parent directory if needed
        let parentDir = destinationPath.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Remove existing binary if present
        if fm.fileExists(atPath: destinationPath.path) {
            try fm.removeItem(at: destinationPath)
        }

        // Copy new binary
        try fm.copyItem(at: sourcePath, to: destinationPath)

        // Set executable permissions
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath.path)
    }

    /// Checks if a file is executable.
    /// - Parameter path: The file path to check.
    /// - Returns: True if the file exists and is executable.
    private func isExecutable(at path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }

        do {
            let attrs = try fm.attributesOfItem(atPath: path)
            if let permissions = attrs[.posixPermissions] as? NSNumber {
                // Check if any execute bit is set (owner, group, or others)
                return permissions.intValue & 0o111 != 0
            }
        } catch {
            return false
        }
        return false
    }
}
