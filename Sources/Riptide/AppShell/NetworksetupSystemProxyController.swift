import Foundation

/// Controls the macOS system proxy via `networksetup` run **directly** — no
/// `sudo`, no privileged helper.
///
/// On modern macOS an administrator user can change proxy settings with
/// `networksetup` without root (verified empirically: `-setwebproxy` /
/// `-setsocksfirewallproxy` succeed for an admin with exit code 0). In
/// system-proxy mode mihomo only opens local listeners, so neither the proxy
/// mutation nor the sidecar needs elevation.
///
/// This replaces the previous helper-or-sudo path, which could not function
/// from the (sandbox-less) GUI app: the SMJobBless helper was never installable
/// in shipped builds, and a GUI `sudo` invocation has no controlling TTY and no
/// askpass, so it cannot prompt for a password. The result was that
/// system-proxy mode silently failed to set the proxy at all.
///
/// Command execution is injected (`CommandRunner`) so tests can assert the exact
/// commands without mutating the real system.
public final class NetworksetupSystemProxyController: SystemProxyControlling, @unchecked Sendable {

    /// Result of running a command: exit code + combined stdout/stderr.
    public struct CommandResult: Sendable {
        public let exitCode: Int32
        public let output: String
        public init(exitCode: Int32, output: String) {
            self.exitCode = exitCode
            self.output = output
        }
    }

    /// Runs an executable with arguments and returns its result.
    /// Injectable so tests can record commands without touching the system.
    public typealias CommandRunner = @Sendable (_ path: String, _ args: [String]) async -> CommandResult

    private let networksetup = "/usr/sbin/networksetup"
    private let runner: CommandRunner

    // Mutable state guarded by a lock for `@unchecked Sendable` safety.
    private let lock = NSLock()
    private var _state: SystemProxyState = .disabled
    private var cachedService: String?

    /// - Parameter runner: command executor; defaults to a real `Process` runner
    ///   that invokes `networksetup` directly (never `sudo`).
    public init(runner: @escaping CommandRunner = NetworksetupSystemProxyController.defaultRunner) {
        self.runner = runner
    }

    // MARK: - SystemProxyControlling

    public func enable(httpPort: Int, socksPort: Int?) async throws {
        let service = await resolveService()
        let host = "127.0.0.1"

        // Each `-setX` command both sets the host/port and enables that proxy type.
        try await run(["-setwebproxy", service, host, "\(httpPort)"])
        try await run(["-setsecurewebproxy", service, host, "\(httpPort)"])
        if let socksPort {
            try await run(["-setsocksfirewallproxy", service, host, "\(socksPort)"])
        }

        setState(.enabled(httpPort: httpPort, socksPort: socksPort))
    }

    public func disable() async throws {
        let service = await resolveService()
        // Best-effort: turn every proxy type off, regardless of which were on.
        _ = try? await run(["-setwebproxystate", service, "off"])
        _ = try? await run(["-setsecurewebproxystate", service, "off"])
        _ = try? await run(["-setsocksfirewallproxystate", service, "off"])
        setState(.disabled)
    }

    public func currentState() -> SystemProxyState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Reads the live macOS web-proxy port for the primary service, or nil when
    /// the proxy is disabled/unreadable. Used at launch to detect a stale proxy
    /// left behind by a crashed/force-quit session.
    public func activeHTTPProxyPort() async -> Int? {
        let service = await resolveService()
        let result = await runner(networksetup, ["-getwebproxy", service])
        guard result.exitCode == 0 else { return nil }
        return Self.parseEnabledPort(from: result.output)
    }

    /// Parses `networksetup -getwebproxy` output, returning the port only when the
    /// proxy is enabled. Example input:
    /// `Enabled: Yes\nServer: 127.0.0.1\nPort: 6152\n...`
    static func parseEnabledPort(from output: String) -> Int? {
        var enabled = false
        var port: Int?
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Enabled:") {
                enabled = line.lowercased().contains("yes")
            } else if line.hasPrefix("Port:") {
                port = Int(line.dropFirst("Port:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return enabled ? port : nil
    }

    // MARK: - Internals

    @discardableResult
    private func run(_ args: [String]) async throws -> CommandResult {
        let result = await runner(networksetup, args)
        guard result.exitCode == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemProxyError.unknown(
                "networksetup \(args.first ?? "") failed (exit \(result.exitCode))"
                    + (detail.isEmpty ? "" : ": \(detail)")
            )
        }
        return result
    }

    /// Resolves the primary active network service (e.g. "Wi-Fi"), cached after
    /// first detection. Falls back to "Wi-Fi" if detection yields nothing.
    private func resolveService() async -> String {
        if let cached = cachedServiceSnapshot() { return cached }
        let result = await runner(networksetup, ["-listallnetworkservices"])
        let service = Self.firstActiveService(from: result.output) ?? "Wi-Fi"
        cacheService(service)
        return service
    }

    /// Parses `networksetup -listallnetworkservices` output, returning the first
    /// **enabled** service. The first line is a header; disabled services are
    /// prefixed with `*`.
    static func firstActiveService(from output: String) -> String? {
        let lines = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines.dropFirst() where !line.isEmpty && !line.hasPrefix("*") {
            return line
        }
        return nil
    }

    private func setState(_ newState: SystemProxyState) {
        lock.lock(); _state = newState; lock.unlock()
    }

    private func cachedServiceSnapshot() -> String? {
        lock.lock(); defer { lock.unlock() }
        return cachedService
    }

    private func cacheService(_ service: String) {
        lock.lock(); cachedService = service; lock.unlock()
    }

    // MARK: - Default Runner

    /// Default runner that executes `networksetup` via `Process` **without** sudo.
    public static let defaultRunner: CommandRunner = { path, args in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: CommandResult(
                        exitCode: proc.terminationStatus,
                        output: output
                    ))
                } catch {
                    continuation.resume(returning: CommandResult(
                        exitCode: -1,
                        output: error.localizedDescription
                    ))
                }
            }
        }
    }
}
