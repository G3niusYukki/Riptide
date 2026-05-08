import Foundation
import ServiceManagement
import Security
import Combine

/// Manages the installation and status checking of the privileged helper tool.
///
/// Uses `SMAppService.daemon()` on macOS 13+ for a modern, system-managed experience.
/// Falls back to `SMJobBless` on older systems.
final class SMJobBlessManager: ObservableObject {
    @Published var isHelperInstalled: Bool = false
    @Published var installationError: String?
    @Published var isInstalling: Bool = false

    private let helperLabel = "com.riptide.helper"
    private let plistName = "com.riptide.helper.plist"

    init() {
        checkHelperStatus()
    }

    // MARK: - Status Check

    /// Checks whether the privileged helper tool is currently registered.
    func checkHelperStatus() {
        if #available(macOS 13.0, *) {
            checkHelperStatusModern()
        } else {
            checkHelperStatusLegacy()
        }
    }

    @available(macOS 13.0, *)
    private func checkHelperStatusModern() {
        let service = SMAppService.daemon(plistName: plistName)
        isHelperInstalled = service.status == .enabled
    }

    private func checkHelperStatusLegacy() {
        guard let jobDict = SMJobCopyDictionary(kSMDomainSystemLaunchd, helperLabel as CFString)?.takeRetainedValue() as? [String: Any] else {
            isHelperInstalled = false
            return
        }
        let enabled = jobDict["Enabled"] as? Bool ?? true
        isHelperInstalled = enabled
    }

    // MARK: - Installation

    /// Installs the privileged helper tool.
    /// On macOS 13+, uses `SMAppService.daemon()` for system-managed installation.
    /// Falls back to `SMJobBless` on older systems.
    func installHelper() {
        guard !isInstalling else { return }

        isInstalling = true
        installationError = nil

        if #available(macOS 13.0, *) {
            installHelperModern()
        } else {
            installHelperLegacy()
        }
    }

    @available(macOS 13.0, *)
    private func installHelperModern() {
        let service = SMAppService.daemon(plistName: plistName)

        do {
            try service.register()
            checkHelperStatus()

            if !isHelperInstalled {
                installationError = "Registration appeared to succeed but helper is not enabled. Please try again."
            }
        } catch {
            installationError = "Failed to install helper: \(error.localizedDescription)"
        }

        isInstalling = false
    }

    private func installHelperLegacy() {
        do {
            var authRef: AuthorizationRef?
            let authStatus = AuthorizationCreate(nil, nil, [], &authRef)

            guard authStatus == errAuthorizationSuccess, let authorization = authRef else {
                throw InstallationError.authorizationFailed(status: authStatus)
            }

            defer { AuthorizationFree(authorization, []) }

            let success = kSMRightBlessPrivilegedHelper.withCString { rightPointer in
                let authItem = AuthorizationItem(name: rightPointer, valueLength: 0, value: nil, flags: 0)
                var authItems = [authItem]

                return authItems.withUnsafeMutableBufferPointer { itemsBuffer in
                    var authRights = AuthorizationRights(count: 1, items: itemsBuffer.baseAddress)

                    let flags: AuthorizationFlags = [
                        .interactionAllowed,
                        .extendRights,
                        .preAuthorize
                    ]

                    let authStatus = AuthorizationCopyRights(authorization, &authRights, nil, flags, nil)

                    guard authStatus == errAuthorizationSuccess else {
                        return false
                    }

                    var cfError: Unmanaged<CFError>?
                    let blessSuccess = SMJobBless(kSMDomainSystemLaunchd, helperLabel as CFString, authorization, &cfError)

                    if let error = cfError?.takeRetainedValue() {
                        self.installationError = "Failed to install helper: \(error.localizedDescription)"
                        return false
                    }

                    return blessSuccess
                }
            }

            guard success else {
                if installationError == nil {
                    installationError = "Failed to install helper: Authorization or blessing failed"
                }
                return
            }

            checkHelperStatus()

            if !isHelperInstalled {
                throw InstallationError.verificationFailed
            }

        } catch let error as InstallationError {
            installationError = error.localizedDescription
        } catch {
            installationError = "Unexpected error: \(error.localizedDescription)"
        }

        isInstalling = false
    }

    // MARK: - Removal

    /// Removes the privileged helper tool (for testing/debugging purposes).
    func removeHelper() {
        guard !isInstalling else { return }

        isInstalling = true
        installationError = nil

        if #available(macOS 13.0, *) {
            removeHelperModern()
        } else {
            removeHelperLegacy()
        }
    }

    @available(macOS 13.0, *)
    private func removeHelperModern() {
        let service = SMAppService.daemon(plistName: plistName)

        do {
            try service.unregister()
            checkHelperStatus()
        } catch {
            installationError = "Failed to remove helper: \(error.localizedDescription)"
        }

        isInstalling = false
    }

    private func removeHelperLegacy() {
        do {
            var authRef: AuthorizationRef?
            let authStatus = AuthorizationCreate(nil, nil, [], &authRef)

            guard authStatus == errAuthorizationSuccess, let authorization = authRef else {
                throw InstallationError.authorizationFailed(status: authStatus)
            }

            defer { AuthorizationFree(authorization, []) }

            var cfError: Unmanaged<CFError>?
            let success = SMJobRemove(kSMDomainSystemLaunchd, helperLabel as CFString, authorization, true, &cfError)

            if let error = cfError?.takeRetainedValue() {
                throw InstallationError.removalFailed(error: error)
            }

            guard success else {
                throw InstallationError.removalFailed(error: nil)
            }

            checkHelperStatus()

        } catch let error as InstallationError {
            installationError = error.localizedDescription
        } catch {
            installationError = "Unexpected error: \(error.localizedDescription)"
        }

        isInstalling = false
    }
}

// MARK: - Installation Errors

extension SMJobBlessManager {
    enum InstallationError: Error {
        case authorizationFailed(status: OSStatus)
        case blessFailed(error: CFError?)
        case verificationFailed
        case removalFailed(error: CFError?)

        var localizedDescription: String {
            switch self {
            case .authorizationFailed(let status):
                return "Authorization failed (error code: \(status)). Please try again."
            case .blessFailed(let error):
                if let error = error {
                    return "Failed to install helper: \(error.localizedDescription)"
                }
                return "Failed to install helper: Unknown error"
            case .verificationFailed:
                return "Installation appeared to succeed but helper is not registered. Please try again."
            case .removalFailed(let error):
                if let error = error {
                    return "Failed to remove helper: \(error.localizedDescription)"
                }
                return "Failed to remove helper: Unknown error"
            }
        }
    }
}
