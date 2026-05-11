import Foundation

/// Manages automatic backups of configuration files.
/// Backups are stored in ~/Library/Application Support/Riptide/backups/
/// Each backup is a YAML file named with an ISO 8601 timestamp.
public actor ConfigBackupManager {
    private let backupDirectory: URL
    private let maxBackups: Int

    /// Creates a new ConfigBackupManager.
    /// - Parameter maxBackups: Maximum number of backups to retain (default 20).
    public init(maxBackups: Int = 20) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")

        self.backupDirectory = appSupport
            .appendingPathComponent("Riptide", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
        self.maxBackups = maxBackups
    }

    // MARK: - Backup

    /// Create a backup of the given YAML config.
    /// - Parameters:
    ///   - yaml: The config YAML string.
    ///   - name: Optional name tag (e.g. profile name).
    /// - Returns: The URL of the created backup file.
    @discardableResult
    public func backup(yaml: String, name: String? = nil) throws -> URL {
        try createBackupDirectoryIfNeeded()

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeName = name.map { "-\($0)" } ?? ""
        let fileName = "config-\(timestamp)\(safeName).yaml"
        let fileURL = backupDirectory.appendingPathComponent(fileName)

        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)

        // Prune old backups
        try pruneOldBackups()

        return fileURL
    }

    // MARK: - List

    /// List all available backups, most recent first.
    public func listBackups() throws -> [ConfigBackup] {
        try createBackupDirectoryIfNeeded()

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let backups: [ConfigBackup] = files.compactMap { url in
            guard url.pathExtension == "yaml" else { return nil }

            let resources = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let size = resources?.fileSize ?? 0

            return ConfigBackup(
                url: url,
                name: parseBackupName(from: url),
                createdAt: parseBackupDate(from: url) ?? resources?.creationDate ?? Date(),
                fileSize: size
            )
        }

        return backups.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Restore

    /// Restore a config from a backup file.
    /// - Parameter backup: The backup to restore.
    /// - Returns: The YAML content of the backup.
    public func restore(from backup: ConfigBackup) throws -> String {
        try String(contentsOf: backup.url, encoding: .utf8)
    }

    // MARK: - Delete

    /// Delete a specific backup.
    public func delete(_ backup: ConfigBackup) throws {
        try FileManager.default.removeItem(at: backup.url)
    }

    /// Delete all backups.
    public func deleteAll() throws {
        try createBackupDirectoryIfNeeded()
        let files = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func createBackupDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
    }

    private func pruneOldBackups() throws {
        let backups = try listBackups()
        guard backups.count > maxBackups else { return }

        let toDelete = backups.suffix(backups.count - maxBackups)
        for backup in toDelete {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    private func parseBackupDate(from url: URL) -> Date? {
        let fileName = url.deletingPathExtension().lastPathComponent
        // Expected format: config-2024-01-01T00:00:00Z-name
        let components = fileName.split(separator: "-", maxSplits: 2)
        guard components.count >= 2 else { return nil }

        // Try to parse the ISO 8601 date portion
        let dateStr = String(components[1])
        return ISO8601DateFormatter().date(from: dateStr)
    }

    private func parseBackupName(from url: URL) -> String {
        let fileName = url.deletingPathExtension().lastPathComponent
        let components = fileName.split(separator: "-", maxSplits: 2)
        guard components.count >= 3 else { return "unnamed" }
        return String(components[2])
    }
}

// MARK: - Backup Model

/// A configuration backup entry.
public struct ConfigBackup: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let createdAt: Date
    public let fileSize: Int

    public init(url: URL, name: String, createdAt: Date, fileSize: Int) {
        self.url = url
        self.name = name
        self.createdAt = createdAt
        self.fileSize = fileSize
    }

    /// Human-readable file size.
    public var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}
