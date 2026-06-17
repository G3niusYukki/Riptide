import Foundation
import Riptide

// MARK: - Mihomo Core Management

extension AppViewModel {

    /// Checks mihomo status on launch and downloads if needed.
    public func checkMihomoOnLaunch() async {
        let paths = MihomoPaths()
        let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path

        if !FileManager.default.fileExists(atPath: mihomoPath) {
            // First launch - no kernel installed
            await downloadLatestMihomo(channel: mihomoChannel)
        } else {
            // Check current version
            let version = getCurrentMihomoVersion(executablePath: mihomoPath)
            await MainActor.run {
                self.mihomoVersion = version
            }

            // Check for updates
            let downloader = MihomoDownloader()
            if let update = await downloader.checkForUpdate(currentVersion: version, channel: mihomoChannel) {
                await MainActor.run {
                    self.availableUpdate = update
                    self.mihomoDownloadError = nil
                }
            }
        }

    }

    /// Downloads the latest mihomo version.
    public func downloadLatestMihomo(channel: MihomoDownloader.Channel? = nil) async {
        let effectiveChannel = channel ?? mihomoChannel

        await MainActor.run {
            isDownloadingMihomo = true
            mihomoDownloadProgress = 0
            mihomoDownloadError = nil
        }

        defer {
            Task { @MainActor in
                isDownloadingMihomo = false
            }
        }

        do {
            let downloader = MihomoDownloader(progressDelegate: self)
            let downloadedPath = try await downloader.downloadLatest(channel: effectiveChannel)

            // Replace current kernel
            try replaceCurrentMihomo(with: downloadedPath)

            // Update version info
            let paths = MihomoPaths()
            let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
            let newVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

            await MainActor.run {
                mihomoVersion = newVersion
                availableUpdate = nil
                mihomoDownloadProgress = 1.0
            }
        } catch {
            await MainActor.run {
                mihomoDownloadError = error.localizedDescription
            }
        }
    }

    /// Switches to a specific mihomo version.
    public func switchMihomoVersion(to version: String) async {
        // 1. Stop current proxy if running
        if tunnelState == .running {
            await stop()
        }

        // 2. Check if version is already downloaded
        let downloader = MihomoDownloader()
        if let existingPath = downloader.pathForVersion(version) {
            do {
                try replaceCurrentMihomo(with: existingPath)

                let paths = MihomoPaths()
                let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
                let currentVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

                await MainActor.run {
                    mihomoVersion = currentVersion
                    availableUpdate = nil
                }
            } catch {
                await MainActor.run {
                    mihomoDownloadError = error.localizedDescription
                }
            }
            return
        }

        // 3. Download the specified version
        await MainActor.run {
            isDownloadingMihomo = true
            mihomoDownloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloadingMihomo = false
            }
        }

        do {
            let downloadedPath = try await downloader.downloadVersion(version)
            try replaceCurrentMihomo(with: downloadedPath)

            let paths = MihomoPaths()
            let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
            let currentVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

            await MainActor.run {
                mihomoVersion = currentVersion
                availableUpdate = nil
            }
        } catch {
            await MainActor.run {
                mihomoDownloadError = error.localizedDescription
            }
        }
    }

    /// Lists all locally available mihomo versions.
    public func listLocalMihomoVersions() -> [String] {
        let downloader = MihomoDownloader()
        return downloader.listLocalVersions()
    }
}
