// swiftlint:disable:this file_length
import Foundation

// MARK: - Path Validation

/// Validates that a path is within the allowed whitelist.
/// This is a critical security check since the helper runs as root.
enum PathValidator {

    /// Allowed path for mihomo binary installation.
    static let allowedInstallPath = "/Library/Application Support/Riptide/"

    /// Validates that a config path is within allowed directories.
    /// - Parameter path: The path to validate
    /// - Returns: true if the path is allowed
    static func isValidConfigPath(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        // Must be within Application Support/Riptide/mihomo for configs
        let allowedBase = "Application Support/Riptide/mihomo"
        if normalizedPath.contains(allowedBase) {
            return true
        }

        // Also allow /Library/Application Support/Riptide/ for system-level configs
        if normalizedPath.hasPrefix(allowedInstallPath) {
            return true
        }

        return false
    }

    /// Validates that a binary path is within allowed directories.
    /// - Parameter path: The path to validate
    /// - Returns: true if the path is allowed
    static func isValidBinaryPath(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        // Only allow installation to the system Riptide directory
        return normalizedPath.hasPrefix(allowedInstallPath)
    }
}

// MARK: - Helper Tool Protocol (must be defined in this module for XPC)

/// XPC protocol for the privileged helper tool that manages mihomo core.
@objc(HelperToolProtocol)
protocol HelperToolProtocol {
    func launchMihomo(configPath: String, mode: String, reply: @escaping @Sendable (Error?) -> Void)
    func terminateMihomo(reply: @escaping @Sendable (Error?) -> Void)
    func getMihomoStatus(reply: @escaping @Sendable (Data?, Error?) -> Void)
    func installMihomo(binaryPath: String, reply: @escaping @Sendable (Error?) -> Void)

    // MARK: - System Proxy Control

    func enableSystemProxy(service: String, httpPort: Int, socksPort: Int, reply: @escaping @Sendable (Error?) -> Void)
    func disableSystemProxy(service: String, reply: @escaping @Sendable (Error?) -> Void)
    func querySystemProxyState(service: String, reply: @escaping @Sendable (String?, Error?) -> Void)
    func detectNetworkService(reply: @escaping @Sendable (String?, Error?) -> Void)
}

// MARK: - Launch Mode

/// Launch modes for mihomo core.
enum MihomoLaunchMode: String, Sendable, Codable {
    case systemProxy
    case tun
}

// MARK: - Status

/// Current status of the mihomo process.
struct MihomoStatus: Codable, Sendable {
    let running: Bool
    let pid: Int?
    let mode: String?
    let configPath: String?
    let startTime: Date?
}

// MARK: - Helper Tool

/// The main helper tool class that manages the XPC service.
/// This runs as a root-privileged daemon via SMJobBless.
@MainActor
final class HelperTool: NSObject {

    // MARK: - Properties

    /// The XPC listener for incoming connections.
    private var listener: NSXPCListener?

    /// The mihomo launcher actor.
    private let launcher = MihomoLauncher()

    // MARK: - Main Entry

    /// Runs the helper tool XPC service.
    nonisolated func run() {
        // Create the XPC listener (must happen before setting delegate)
        let newListener = NSXPCListener(machServiceName: "com.riptide.helper")

        // Log startup (must be done non-isolated)
        logMessageNonIsolated("RiptideHelper starting...")

        // Set up the listener on the main actor
        Task { @MainActor in
            self.listener = newListener
            newListener.delegate = self
            newListener.resume()
        }

        // Keep the run loop running (this blocks, so we do it after setup)
        RunLoop.current.run()
    }

    // MARK: - Logging

    /// Logs a message to the system log (non-isolated version for use in nonisolated contexts).
    nonisolated private func logMessageNonIsolated(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[RiptideHelper] [\(timestamp)] \(message)\n"

        // Write to stderr which is captured by launchd
        if let data = logEntry.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }

        // Also attempt to write to log file
        let logURL = URL(fileURLWithPath: "/Library/Application Support/Riptide/logs/helper.log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        if let handle = try? FileHandle(forWritingTo: logURL),
           let data = logEntry.data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    /// Logs a message (MainActor version).
    private func logMessage(_ message: String) {
        logMessageNonIsolated(message)
    }

    // MARK: - Networksetup

    /// Runs `/usr/sbin/networksetup` with the given arguments.
    /// - Parameter arguments: Arguments to pass to networksetup
    /// - Returns: nil on success, Error on failure
    nonisolated private func runNetworksetup(_ arguments: [String]) -> Error? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return NSError(
                    domain: "RiptideHelper",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "networksetup failed: exit \(process.terminationStatus)"]
                )
            }
            return nil
        } catch {
            return error
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension HelperTool: NSXPCListenerDelegate {

    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Configure the connection with the helper tool protocol
        let interface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self

        // Set up the remote object interface (for callbacks if needed)
        newConnection.remoteObjectInterface = nil

        // Set up invalidation handler
        newConnection.invalidationHandler = { [weak self] in
            self?.logMessageNonIsolated("XPC connection invalidated")
        }

        // Set up interruption handler
        newConnection.interruptionHandler = { [weak self] in
            self?.logMessageNonIsolated("XPC connection interrupted")
        }

        logMessageNonIsolated("Accepted new XPC connection")
        newConnection.resume()
        return true
    }
}

// MARK: - HelperToolProtocol

extension HelperTool: HelperToolProtocol {

    nonisolated func launchMihomo(configPath: String, mode: String, reply: @escaping @Sendable (Error?) -> Void) {
        logMessageNonIsolated("Received launchMihomo request - config: \(configPath), mode: \(mode)")

        // Validate mode using MihomoLaunchMode enum
        guard MihomoLaunchMode(rawValue: mode) != nil else {
            let error = NSError(
                domain: "RiptideHelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid mode: \(mode)"]
            )
            logMessageNonIsolated("Launch failed: invalid mode \(mode)")
            reply(error)
            return
        }

        // Validate config path is in whitelist
        guard PathValidator.isValidConfigPath(configPath) else {
            let error = NSError(
                domain: "RiptideHelper",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Config path not in whitelist: \(configPath)"]
            )
            logMessageNonIsolated("Launch failed: path not in whitelist \(configPath)")
            reply(error)
            return
        }

        // Validate config file exists
        guard FileManager.default.fileExists(atPath: configPath) else {
            let error = NSError(
                domain: "RiptideHelper",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Config file does not exist: \(configPath)"]
            )
            logMessageNonIsolated("Launch failed: config file does not exist \(configPath)")
            reply(error)
            return
        }

        // Launch mihomo on MainActor
        Task { @MainActor [launcher] in
            do {
                try await launcher.launch(configPath: configPath, mode: mode)
                reply(nil)
            } catch let error as MihomoLauncherError {
                let nsError = NSError(
                    domain: "RiptideHelper",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Launch failed: \(error)"]
                )
                reply(nsError)
            } catch {
                let nsError = NSError(
                    domain: "RiptideHelper",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Launch failed: \(error.localizedDescription)"]
                )
                reply(nsError)
            }
        }
    }

    nonisolated func terminateMihomo(reply: @escaping @Sendable (Error?) -> Void) {
        logMessageNonIsolated("Received terminateMihomo request")

        Task { @MainActor [launcher] in
            do {
                try await launcher.terminate()
                reply(nil)
            } catch let error as MihomoLauncherError {
                let nsError = NSError(
                    domain: "RiptideHelper",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Termination failed: \(error)"]
                )
                reply(nsError)
            } catch {
                let nsError = NSError(
                    domain: "RiptideHelper",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Termination failed: \(error.localizedDescription)"]
                )
                reply(nsError)
            }
        }
    }

    nonisolated func getMihomoStatus(reply: @escaping @Sendable (Data?, Error?) -> Void) {
        logMessageNonIsolated("Received getMihomoStatus request")

        Task { @MainActor [launcher] in
            let status = await launcher.getStatus()

            // Create status struct
            let statusStruct = MihomoStatus(
                running: status.running,
                pid: status.pid,
                mode: status.mode,
                configPath: status.configPath,
                startTime: status.startTime
            )

            // Encode to JSON
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(statusStruct)
                reply(data, nil)
            } catch {
                let nsError = NSError(
                    domain: "RiptideHelper",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode status: \(error.localizedDescription)"]
                )
                reply(nil, nsError)
            }
        }
    }

    nonisolated func installMihomo(binaryPath: String, reply: @escaping @Sendable (Error?) -> Void) {
        logMessageNonIsolated("Received installMihomo request - binary: \(binaryPath)")

        // Validate source path exists
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            let error = NSError(
                domain: "RiptideHelper",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Binary does not exist: \(binaryPath)"]
            )
            logMessageNonIsolated("Install failed: binary does not exist \(binaryPath)")
            reply(error)
            return
        }

        // Validate destination is in whitelist
        let destinationPath = MihomoLauncher.defaultBinaryPath
        guard PathValidator.isValidBinaryPath(destinationPath) else {
            let error = NSError(
                domain: "RiptideHelper",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Destination path not in whitelist: \(destinationPath)"]
            )
            logMessageNonIsolated("Install failed: destination not in whitelist")
            reply(error)
            return
        }

        // Perform installation
        do {
            let fileManager = FileManager.default
            let destURL = URL(fileURLWithPath: destinationPath)

            // Create directory if needed
            try fileManager.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Remove existing binary if present
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }

            // Copy new binary
            try fileManager.copyItem(atPath: binaryPath, toPath: destinationPath)

            // Set executable permissions
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: 0o755
            ]
            try fileManager.setAttributes(attrs, ofItemAtPath: destinationPath)

            logMessageNonIsolated("Mihomo installed successfully to \(destinationPath)")
            reply(nil)
        } catch {
            let nsError = NSError(
                domain: "RiptideHelper",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Installation failed: \(error.localizedDescription)"]
            )
            logMessageNonIsolated("Install failed: \(error)")
            reply(nsError)
        }
    }

    // MARK: - System Proxy Control

    nonisolated func enableSystemProxy(
        service: String, httpPort: Int, socksPort: Int,
        reply: @escaping @Sendable (Error?) -> Void
    ) {
        logMessageNonIsolated("enableSystemProxy - service: \(service), http: \(httpPort), socks: \(socksPort)")
        if let err = runNetworksetup(["-setwebproxy", service, "127.0.0.1", "\(httpPort)"]) { reply(err); return }
        if let err = runNetworksetup(["-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"]) { reply(err); return }
        if socksPort > 0 {
            if let err = runNetworksetup(
                ["-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"]
            ) { reply(err); return }
        }
        reply(nil)
    }

    nonisolated func disableSystemProxy(service: String, reply: @escaping @Sendable (Error?) -> Void) {
        logMessageNonIsolated("disableSystemProxy - service: \(service)")
        let webError = runNetworksetup(["-setwebproxystate", service, "off"])
        let secureError = runNetworksetup(["-setsecurewebproxystate", service, "off"])
        let socksError = runNetworksetup(["-setsocksfirewallproxystate", service, "off"])
        reply(webError ?? secureError ?? socksError)
    }

    nonisolated func querySystemProxyState(service: String, reply: @escaping @Sendable (String?, Error?) -> Void) {
        logMessageNonIsolated("querySystemProxyState - service: \(service)")

        let httpResult = runNetworksetupCapture(["-getwebproxy", service])
        let socksResult = runNetworksetupCapture(["-getsocksfirewallproxy", service])

        guard let httpOutput = httpResult.output else {
            reply(nil, httpResult.error ?? NSError(domain: "RiptideHelper", code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Failed to query HTTP proxy state"]))
            return
        }
        guard let socksOutput = socksResult.output else {
            reply(nil, socksResult.error ?? NSError(domain: "RiptideHelper", code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Failed to query SOCKS proxy state"]))
            return
        }

        let httpEnabled = httpOutput.range(of: "Enabled: Yes", options: .caseInsensitive) != nil
        let socksEnabled = socksOutput.range(of: "Enabled: Yes", options: .caseInsensitive) != nil
        let httpPort = parsePort(from: httpOutput) ?? 0
        let socksPort = parsePort(from: socksOutput) ?? 0

        let json = """
        {"httpEnabled":\(httpEnabled),"httpPort":\(httpPort),"socksEnabled":\(socksEnabled),"socksPort":\(socksPort)}
        """
        reply(json, nil)
    }

    nonisolated func detectNetworkService(reply: @escaping @Sendable (String?, Error?) -> Void) {
        logMessageNonIsolated("detectNetworkService")

        let result = runNetworksetupCapture(["-listallnetworkservices"])
        guard let output = result.output else {
            reply(nil, result.error ?? NSError(domain: "RiptideHelper", code: 22,
                userInfo: [NSLocalizedDescriptionKey: "Failed to list network services"]))
            return
        }

        let lines = output.components(separatedBy: .newlines)
        for line in lines.dropFirst() { // skip "An asterisk (*) denotes..."
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("*") {
                logMessageNonIsolated("Detected network service: \(trimmed)")
                reply(trimmed, nil)
                return
            }
        }

        reply(nil, NSError(domain: "RiptideHelper", code: 23,
            userInfo: [NSLocalizedDescriptionKey: "No active network service found"]))
    }

    // MARK: - Networksetup Helpers

    /// Runs networksetup and captures stdout.
    nonisolated private func runNetworksetupCapture(_ arguments: [String]) -> (output: String?, error: Error?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            if process.terminationStatus != 0 {
                let error = NSError(domain: "RiptideHelper", code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "networksetup failed: exit \(process.terminationStatus)"])
                return (output, error)
            }
            return (output, nil)
        } catch {
            return (nil, error)
        }
    }

    /// Parses the port number from networksetup output (e.g. "Port: 7890").
    nonisolated private func parsePort(from output: String) -> Int? {
        for line in output.components(separatedBy: .newlines) where line.hasPrefix("Port:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }
}
