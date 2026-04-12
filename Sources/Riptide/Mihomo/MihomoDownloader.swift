import Foundation

// MARK: - Error Types

/// Errors that can occur during mihomo download operations.
public enum DownloadError: Error, Equatable, Sendable {
    /// Failed to fetch release information from GitHub.
    case fetchFailed
    /// No asset found for the current platform.
    case assetNotFound
    /// Failed to download the file.
    case downloadFailed
    /// Failed to decompress the gz file.
    case decompressionFailed
    /// Failed to write file to disk.
    case fileWriteFailed
    /// Invalid version string.
    case invalidVersion(String)
}

// MARK: - Platform

/// Supported platforms for mihomo binary downloads.
public enum Platform: Sendable {
    case macOS, windows, linux

    /// The asset name pattern to match in GitHub releases.
    var assetName: String {
        switch self {
        case .macOS: return "darwin"
        case .windows: return "windows"
        case .linux: return "linux"
        }
    }

    /// The expected binary name after extraction.
    var binaryName: String {
        switch self {
        case .macOS, .linux: return "mihomo"
        case .windows: return "mihomo.exe"
        }
    }
}

// MARK: - Release Channel

extension MihomoDownloader {
    /// Release channel for mihomo downloads.
    public enum Channel: String, CaseIterable, Sendable {
        /// Stable releases (latest).
        case stable = "latest"
        /// Alpha/prerelease builds.
        case alpha = "tags/Prerelease-Alpha"
    }
}

// MARK: - Update Info

extension MihomoDownloader {
    /// Information about an available update.
    public struct UpdateInfo: Codable, Sendable {
        /// The version tag (e.g., "v1.18.0").
        public let version: String
        /// URL to download the update.
        public let downloadURL: URL
        /// Release notes/description.
        public let releaseNotes: String?
        /// Publication date.
        public let publishedAt: Date

        public init(version: String, downloadURL: URL, releaseNotes: String?, publishedAt: Date) {
            self.version = version
            self.downloadURL = downloadURL
            self.releaseNotes = releaseNotes
            self.publishedAt = publishedAt
        }
    }
}

// MARK: - GitHub API Models

/// GitHub release response model.
struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let body: String?
    let publishedAt: Date
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case publishedAt = "published_at"
        case assets
    }
}

/// GitHub release asset model.
struct GitHubAsset: Codable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

// MARK: - Download Progress

/// Protocol for receiving download progress updates.
public protocol MihomoDownloadProgressDelegate: Sendable {
    /// Called when download progress updates.
    func downloadProgress(_ bytesDownloaded: Int64, totalBytes: Int64)
}

// MARK: - Mihomo Downloader

/// Actor responsible for downloading and managing mihomo core binaries from GitHub releases.
public actor MihomoDownloader {
    private let githubAPI = "https://api.github.com/repos/MetaCubeX/mihomo/releases"
    /// The directory where mihomo binaries are downloaded.
    public let downloadDir: URL
    private var progressDelegate: MihomoDownloadProgressDelegate?

    /// The URL session used for downloads.
    private let urlSession: URLSession

    /// Creates a new MihomoDownloader instance.
    /// - Parameters:
    ///   - downloadDir: Directory to store downloaded binaries. Defaults to Application Support/Riptide/mihomo/bin.
    ///   - progressDelegate: Optional delegate for progress updates.
    public init(
        downloadDir: URL? = nil,
        progressDelegate: MihomoDownloadProgressDelegate? = nil
    ) {
        self.downloadDir = downloadDir ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Riptide", isDirectory: true)
            .appendingPathComponent("mihomo", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        self.progressDelegate = progressDelegate

        // Create URLSession with custom delegate for progress tracking
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300  // 5 minutes
        configuration.timeoutIntervalForResource = 600  // 10 minutes
        self.urlSession = URLSession(configuration: configuration)
    }

    /// Sets the progress delegate for download updates.
    public func setProgressDelegate(_ delegate: MihomoDownloadProgressDelegate?) {
        self.progressDelegate = delegate
    }
}

// MARK: - Public API

extension MihomoDownloader {
    /// Downloads the latest mihomo version for the specified channel.
    /// - Parameter channel: The release channel (stable or alpha).
    /// - Returns: URL to the downloaded binary.
    /// - Throws: DownloadError if the operation fails.
    public func downloadLatest(channel: Channel = .stable) async throws -> URL {
        let release = try await fetchRelease(channel: channel)
        let platform = currentPlatform()
        let downloadURL = try extractDownloadURL(from: release, for: platform)
        return try await downloadAndExtract(from: downloadURL, version: release.tagName, platform: platform)
    }

    /// Downloads a specific mihomo version.
    /// - Parameter version: The version tag (e.g., "v1.18.0" or "1.18.0").
    /// - Returns: URL to the downloaded binary.
    /// - Throws: DownloadError if the operation fails.
    public func downloadVersion(_ version: String) async throws -> URL {
        let normalizedVersion = version.hasPrefix("v") ? version : "v\(version)"
        let url = URL(string: "\(githubAPI)/tags/\(normalizedVersion)")!

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DownloadError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)

        let platform = currentPlatform()
        let downloadURL = try extractDownloadURL(from: release, for: platform)
        return try await downloadAndExtract(from: downloadURL, version: release.tagName, platform: platform)
    }

    /// Checks for available updates.
    /// - Parameters:
    ///   - currentVersion: The currently installed version (e.g., "1.18.0").
    ///   - channel: The release channel to check.
    /// - Returns: UpdateInfo if an update is available, nil if already up to date or on error.
    public func checkForUpdate(currentVersion: String, channel: Channel = .stable) async -> UpdateInfo? {
        do {
            let release = try await fetchRelease(channel: channel)
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            let normalizedCurrent = currentVersion.replacingOccurrences(of: "v", with: "")

            guard latestVersion != normalizedCurrent else { return nil }

            let platform = currentPlatform()
            let downloadURL = try extractDownloadURL(from: release, for: platform)

            return UpdateInfo(
                version: release.tagName,
                downloadURL: downloadURL,
                releaseNotes: release.body,
                publishedAt: release.publishedAt
            )
        } catch {
            return nil
        }
    }

    /// Lists all locally downloaded versions.
    /// - Returns: Array of version strings (e.g., ["v1.18.0", "v1.17.0"]).
    public nonisolated func listLocalVersions() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: downloadDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents
            .filter { $0.hasDirectoryPath || !$0.pathExtension.isEmpty }
            .compactMap { url -> String? in
                let name = url.deletingPathExtension().lastPathComponent
                // Extract version from "mihomo-v1.18.0" or similar
                if name.hasPrefix("mihomo-") {
                    return String(name.dropFirst("mihomo-".count))
                }
                return nil
            }
            .sorted()
    }

    /// Gets the path to a specific version if it exists locally.
    /// - Parameter version: The version string (e.g., "v1.18.0" or "1.18.0").
    /// - Returns: URL to the binary if found, nil otherwise.
    public nonisolated func pathForVersion(_ version: String) -> URL? {
        let normalizedVersion = version.hasPrefix("v") ? version : "v\(version)"
        let binaryPath = downloadDir
            .appendingPathComponent("mihomo-\(normalizedVersion)")
            .appendingPathComponent(Self.currentPlatformStatic().binaryName)

        guard FileManager.default.fileExists(atPath: binaryPath.path) else { return nil }
        return binaryPath
    }
}

// MARK: - Private Methods

extension MihomoDownloader {
    /// Fetches release information from GitHub API.
    private func fetchRelease(channel: Channel) async throws -> GitHubRelease {
        let url = URL(string: "\(githubAPI)/\(channel.rawValue)")!

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DownloadError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Extracts the download URL for the current platform from release assets.
    private func extractDownloadURL(from release: GitHubRelease, for platform: Platform) throws -> URL {
        let assetName = platform.assetName

        // For macOS, prefer amd64 (Intel) or arm64 (Apple Silicon)
        let arch = currentArchitecture()
        let archPattern = "\(assetName)-\(arch)"

        // First try to find exact match with architecture
        if let asset = release.assets.first(where: { $0.name.contains(archPattern) && $0.name.hasSuffix(".gz") }) {
            return asset.browserDownloadURL
        }

        // Fallback to any asset matching the platform
        guard let asset = release.assets.first(where: { $0.name.contains(assetName) && $0.name.hasSuffix(".gz") }) else {
            throw DownloadError.assetNotFound
        }

        return asset.browserDownloadURL
    }

    /// Downloads and extracts the mihomo binary.
    private func downloadAndExtract(from url: URL, version: String, platform: Platform) async throws -> URL {
        // Create temp directory for download
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let downloadFileURL = tempDir.appendingPathComponent("download.gz")

        // Download with progress tracking
        try await performDownload(from: url, to: downloadFileURL)

        // Create version directory
        let versionDir = downloadDir.appendingPathComponent("mihomo-\(version)")
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)

        let binaryPath = versionDir.appendingPathComponent(platform.binaryName)

        // Extract gz file
        try unzipGzFile(at: downloadFileURL, to: binaryPath)

        // Set executable permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        // Cleanup temp directory
        try? FileManager.default.removeItem(at: tempDir)

        return binaryPath
    }

    /// Performs the actual file download with progress tracking.
    private func performDownload(from url: URL, to destination: URL) async throws {
        let (asyncBytes, response) = try await urlSession.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DownloadError.downloadFailed
        }

        let totalBytes = httpResponse.expectedContentLength
        var downloadedBytes: Int64 = 0

        // Create file handle for writing
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: nil) else {
            throw DownloadError.fileWriteFailed
        }

        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        for try await byte in asyncBytes {
            try handle.write(contentsOf: [byte])
            downloadedBytes += 1

            // Report progress every 64KB
            if downloadedBytes % 65536 == 0 {
                let currentBytes = downloadedBytes
                let currentTotal = totalBytes
                Task {
                    await self.progressDelegate?.downloadProgress(currentBytes, totalBytes: currentTotal)
                }
            }
        }

        // Final progress update
        let finalBytes = downloadedBytes
        let finalTotal = totalBytes
        Task {
            await self.progressDelegate?.downloadProgress(finalBytes, totalBytes: finalTotal)
        }
    }

    /// Returns the current platform.
    private func currentPlatform() -> Platform {
        Self.currentPlatformStatic()
    }

    /// Returns the current platform (static version for nonisolated contexts).
    private static func currentPlatformStatic() -> Platform {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #else
        return .linux
        #endif
    }

    /// Returns the current architecture string for asset matching.
    private func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        return "amd64"  // Default fallback
        #endif
    }
}

// MARK: - Helper Functions

/// Decompresses a gzipped file.
/// - Parameters:
///   - source: Path to the .gz file.
///   - destination: Path where the decompressed file should be written.
/// - Throws: DownloadError if decompression fails.
public func unzipGzFile(at source: URL, to destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
    process.arguments = ["-c", source.path]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw DownloadError.decompressionFailed
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    try data.write(to: destination)
}

/// Gets the current mihomo version by running the binary with -v flag.
/// - Parameter executablePath: Path to the mihomo executable.
/// - Returns: The version string (e.g., "1.18.0") or "unknown".
public func getCurrentMihomoVersion(executablePath: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = ["-v"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return "unknown"
        }

        // Parse version from output like "Mihomo Meta v1.18.0 darwin arm64 with go1.21.5..."
        // Extract the vX.Y.Z pattern
        let pattern = #/v?(\d+\.\d+\.\d+)/#
        if let match = output.firstMatch(of: pattern) {
            return String(match.1)
        }

        // Fallback: return last word if it looks like a version
        let components = output.components(separatedBy: " ")
        if let last = components.last,
           last.contains(".") && last.rangeOfCharacter(from: CharacterSet.letters.inverted) != nil {
            return last
        }

        return output
    } catch {
        return "unknown"
    }
}

/// Replaces the current mihomo binary with a new one, backing up the old version.
/// - Parameter newPath: Path to the new mihomo binary.
/// - Throws: FileManager errors if replacement fails.
public func replaceCurrentMihomo(with newPath: URL) throws {
    let paths = MihomoPaths()
    let currentPath = paths.baseDirectory.appendingPathComponent("mihomo")
    let backupPath = paths.baseDirectory.appendingPathComponent("mihomo.backup")

    let fm = FileManager.default

    // Backup current version if it exists
    if fm.fileExists(atPath: currentPath.path) {
        try? fm.removeItem(at: backupPath)
        try fm.moveItem(at: currentPath, to: backupPath)
    }

    // Copy new version to current location
    try fm.copyItem(at: newPath, to: currentPath)

    // Set executable permissions
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentPath.path)
}
