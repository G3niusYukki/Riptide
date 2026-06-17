import Riptide

// MARK: - MihomoDownloadProgressDelegate

extension AppViewModel: MihomoDownloadProgressDelegate {
    nonisolated public func downloadProgress(_ bytesDownloaded: Int64, totalBytes: Int64) {
        guard totalBytes > 0 else { return }
        let progress = Double(bytesDownloaded) / Double(totalBytes)
        Task { @MainActor in
            self.mihomoDownloadProgress = min(max(progress, 0.0), 1.0)
        }
    }
}
