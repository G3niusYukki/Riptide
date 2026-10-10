import Foundation
import Riptide

// MARK: - Mihomo Service Mode

extension AppViewModel {

    /// Refreshes service-mode state for the settings UI: installed flag from
    /// the filesystem, online flag from a daemon ping.
    public func refreshMihomoServiceStatus() async {
        let installer = mihomoServiceInstaller
        let installed = await installer.isInstalled()
        let online = installed ? await mihomoServiceClient.ping() : false
        await MainActor.run {
            mihomoServiceInstalled = installed
            mihomoServiceOnline = online
        }
    }

    /// Installs the privileged mihomo service daemon. Shows one
    /// administrator-password prompt.
    public func installMihomoService() async {
        await beginServiceModification()
        do {
            guard let binary = MihomoServiceBinaryLocator.locate() else {
                throw MihomoServiceInstaller.InstallerError.binaryNotFound
            }
            try await mihomoServiceInstaller.install(binarySource: binary)
        } catch {
            await reportServiceError(error)
        }
        await refreshMihomoServiceStatus()
        await endServiceModification()
    }

    /// Uninstalls the privileged mihomo service daemon. Shows one
    /// administrator-password prompt.
    public func uninstallMihomoService() async {
        await beginServiceModification()
        do {
            try await mihomoServiceInstaller.uninstall()
        } catch {
            await reportServiceError(error)
        }
        await refreshMihomoServiceStatus()
        await endServiceModification()
    }

    // MARK: - Private

    private func beginServiceModification() async {
        await MainActor.run {
            isModifyingMihomoService = true
            mihomoServiceError = nil
        }
    }

    private func endServiceModification() async {
        await MainActor.run {
            isModifyingMihomoService = false
        }
    }

    private func reportServiceError(_ error: Error) async {
        let message = Self.describeServiceError(error)
        await MainActor.run {
            mihomoServiceError = message
        }
    }

    private static func describeServiceError(_ error: Error) -> String {
        if let installerError = error as? MihomoServiceInstaller.InstallerError {
            switch installerError {
            case .binaryNotFound:
                return "未找到 riptide-mihomo-service 可执行文件"
            case .authorizationCancelled:
                return "已取消授权"
            case .privilegedActionFailed(let detail):
                return "安装服务失败: \(detail)"
            case .writeFailed(let detail):
                return "写入失败: \(detail)"
            }
        }
        return "服务操作失败: \(error.localizedDescription)"
    }
}
