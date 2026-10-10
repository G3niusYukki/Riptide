import Foundation
import Testing
@testable import Riptide

// MARK: - HTTP primitives

@Suite("Unix HTTP request/response primitives")
struct UnixHTTPPrimitivesTests {

    @Test("request parse round-trips method, path, headers, and body framing")
    func requestParse() throws {
        let text = "POST /v1/start HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 15\r\n"
        let request = try #require(UnixHTTPRequest.parse(headerText: text))
        #expect(request.method == "POST")
        #expect(request.path == "/v1/start")
        #expect(request.headers["content-type"] == "application/json")
        #expect(request.headers["CONTENT-LENGTH"] == nil) // keys are lowercased
    }

    @Test("request parse rejects malformed request lines")
    func requestParseMalformed() {
        #expect(UnixHTTPRequest.parse(headerText: "garbage") == nil)
        #expect(UnixHTTPRequest.parse(headerText: "TELEPORT /x HTTP/1.1") == nil)
    }

    @Test("request serialization includes content-length and closes the connection")
    func requestSerialize() throws {
        let request = UnixHTTPRequest(
            method: "POST",
            path: "/v1/stop",
            body: Data("{}".utf8)
        )
        let text = try #require(String(data: request.serialized(), encoding: .utf8))
        #expect(text.hasPrefix("POST /v1/stop HTTP/1.1\r\n"))
        #expect(text.contains("content-length: 2"))
        #expect(text.contains("connection: close"))
        #expect(text.hasSuffix("\r\n\r\n{}"))
    }

    @Test("response serialization and default reasons")
    func responseSerialize() {
        let response = UnixHTTPResponse.json(MihomoServiceProtocol.Health(), status: 200)
        let text = String(data: response.serialized(), encoding: .utf8) ?? ""
        #expect(text.contains("HTTP/1.1 200 OK"))
        #expect(text.contains("content-type: application/json"))
        let conflict = UnixHTTPResponse.error("core already running", status: 409)
        #expect(conflict.reason == "Conflict")
    }
}

// MARK: - Path policy

@Suite("Mihomo service path policy")
struct MihomoServicePathPolicyTests {

    let root = "/Library/Application Support/Riptide"
    let userRoot = "/Users/tester/Library/Application Support/Riptide"

    @Test("core must live under the admin-writable system root")
    func corePaths() throws {
        // Use a temp root with a real file: the policy verifies existence.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let binary = temp.appendingPathComponent("mihomo")
        FileManager.default.createFile(atPath: binary.path, contents: Data())

        #expect(MihomoServicePathPolicy.isAllowedCorePath(binary.path, systemRoot: temp.path))
        #expect(!MihomoServicePathPolicy.isAllowedCorePath("/tmp/mihomo", systemRoot: root))
        // Sibling-directory prefix must not pass.
        let sibling = "/Library/Application Support/RiptideOther/x"
        #expect(!MihomoServicePathPolicy.isAllowedCorePath(sibling, systemRoot: root))
        // Traversal resolves before the check.
        #expect(!MihomoServicePathPolicy.isAllowedCorePath("\(temp.path)/../mihomo", systemRoot: temp.path))
    }

    @Test("core path must reference an existing regular file")
    func coreMustExist() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let binary = temp.appendingPathComponent("mihomo")
        FileManager.default.createFile(atPath: binary.path, contents: Data())

        #expect(MihomoServicePathPolicy.isAllowedCorePath(binary.path, systemRoot: temp.path))
        #expect(!MihomoServicePathPolicy.isAllowedCorePath(
            temp.appendingPathComponent("missing").path,
            systemRoot: temp.path
        ))
    }

    @Test("configs must be Riptide-managed YAML files")
    func configPaths() {
        #expect(MihomoServicePathPolicy.isAllowedConfigPath(
            "\(userRoot)/mihomo/config.yaml", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(MihomoServicePathPolicy.isAllowedConfigPath(
            "\(root)/mihomo/config.yaml", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(!MihomoServicePathPolicy.isAllowedConfigPath(
            "/etc/passwd", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(!MihomoServicePathPolicy.isAllowedConfigPath(
            "\(userRoot)/mihomo/config.json", systemRoot: root, userRoots: [userRoot]
        ))
    }

    @Test("core install sources are limited to managed locations")
    func coreSources() {
        #expect(MihomoServicePathPolicy.isAllowedCoreSource(
            "\(userRoot)/mihomo/mihomo", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(MihomoServicePathPolicy.isAllowedCoreSource(
            "/Applications/Riptide.app/Contents/MacOS/riptide", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(!MihomoServicePathPolicy.isAllowedCoreSource(
            "/tmp/evil", systemRoot: root, userRoots: [userRoot]
        ))
        #expect(!MihomoServicePathPolicy.isAllowedCoreSource(
            "/Users/attacker/malware", systemRoot: root, userRoots: [userRoot]
        ))
    }
}

// MARK: - Supervisor

/// Creates a stub "core" shell script that stays alive until signaled.
/// The stub is placed under `parent` so path-policy tests control whether
/// the source is inside an allowed root.
private func makeStubCore(parent: URL, name: String = "mihomo") throws -> URL {
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let stub = parent.appendingPathComponent(name)
    try "#!/bin/sh\nsleep 30\n".write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    return stub
}

@Suite("Mihomo service supervisor")
struct MihomoServiceSupervisorTests {

    /// Isolated supervisor rooted at a temp dir with an owner-user config dir.
    private func makeEnvironment() throws -> (supervisor: MihomoServiceSupervisor,
                                               root: URL,
                                               userRoot: URL,
                                               config: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-svc-\(UUID().uuidString)", isDirectory: true)
        let systemRoot = base.appendingPathComponent("SystemRoot", isDirectory: true)
        let userRoot = base.appendingPathComponent("UserRoot", isDirectory: true)
        let mihomoDir = userRoot.appendingPathComponent("mihomo", isDirectory: true)
        let logs = base.appendingPathComponent("logs", isDirectory: true)
        for directory in [systemRoot, mihomoDir, logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let config = mihomoDir.appendingPathComponent("config.yaml")
        try "mixed-port: 6152\n".write(to: config, atomically: true, encoding: .utf8)

        let supervisor = MihomoServiceSupervisor(
            systemRoot: systemRoot,
            userRoots: [userRoot.path],
            coreLogURL: logs.appendingPathComponent("mihomo.log")
        )
        return (supervisor, systemRoot, userRoot, config)
    }

    @Test("installCore copies the stub into the system root and is idempotent")
    func installCore() async throws {
        let env = try makeEnvironment()
        let stub = try makeStubCore(parent: env.userRoot.appendingPathComponent("downloads"))

        let first = try await env.supervisor.installCore(
            request: .init(sourcePath: stub.path)
        )
        #expect(first.copied)
        #expect(first.targetPath == env.root.appendingPathComponent("mihomo").path)
        #expect(FileManager.default.isExecutableFile(atPath: first.targetPath))

        let second = try await env.supervisor.installCore(
            request: .init(sourcePath: stub.path)
        )
        #expect(!second.copied) // identical binary → skipped
    }

    @Test("installCore rejects sources outside managed roots")
    func installCoreRejectsForeignSource() async throws {
        let env = try makeEnvironment()
        let foreign = FileManager.default.temporaryDirectory
            .appendingPathComponent("foreign-\(UUID().uuidString)")
        try "bin-sh".write(to: foreign, atomically: true, encoding: .utf8)
        await #expect(throws: MihomoServiceSupervisorError.self) {
            _ = try await env.supervisor.installCore(request: .init(sourcePath: foreign.path))
        }
    }

    @Test("start launches the installed core and reports running status")
    func startStopLifecycle() async throws {
        let env = try makeEnvironment()
        let stub = try makeStubCore(parent: env.userRoot.appendingPathComponent("downloads"))
        let install = try await env.supervisor.installCore(request: .init(sourcePath: stub.path))

        let started = try await env.supervisor.start(
            request: .init(
                corePath: install.targetPath,
                configPath: env.config.path,
                environment: ["MIHOMO_TUN_MODE": "1"]
            )
        )
        #expect(started.running)
        #expect(started.pid != nil)

        // Second start conflicts.
        await #expect(throws: MihomoServiceSupervisorError.alreadyRunning) {
            _ = try await env.supervisor.start(
                request: .init(corePath: install.targetPath, configPath: env.config.path)
            )
        }

        let stopped = try await env.supervisor.stop()
        #expect(!stopped.running)
        let status = await env.supervisor.status()
        #expect(!status.running)
    }

    @Test("start rejects cores outside the system root and missing configs")
    func startValidation() async throws {
        let env = try makeEnvironment()
        let stub = try makeStubCore(parent: env.userRoot.appendingPathComponent("downloads"))
        // Core not installed under the system root → rejected even though it exists.
        await #expect(throws: MihomoServiceSupervisorError.corePathNotAllowed(stub.path)) {
            _ = try await env.supervisor.start(request: .init(
                corePath: stub.path,
                configPath: env.config.path
            ))
        }
        // Config outside managed roots → rejected.
        let install = try await env.supervisor.installCore(request: .init(sourcePath: stub.path))
        await #expect(throws: MihomoServiceSupervisorError.configPathNotAllowed("/etc/hosts.yaml")) {
            _ = try await env.supervisor.start(request: .init(
                corePath: install.targetPath,
                configPath: "/etc/hosts.yaml"
            ))
        }
    }

    @Test("stop when idle reports notRunning")
    func stopIdle() async throws {
        let env = try makeEnvironment()
        await #expect(throws: MihomoServiceSupervisorError.notRunning) {
            _ = try await env.supervisor.stop()
        }
    }
}

// MARK: - Client + server protocol round-trip

@Suite("Mihomo service client/server round-trip")
struct MihomoServiceRoundTripTests {

    /// Boots a UnixHTTPServer wired to a real supervisor (the same wiring the
    /// daemon executable performs) on a temp socket, plus a client.
    private func bootDaemon() throws -> (client: MihomoServiceClient,
                                         supervisor: MihomoServiceSupervisor,
                                         systemRoot: URL,
                                         userRoot: URL,
                                         config: URL,
                                         stop: @Sendable () -> Void) {
        let token = UUID().uuidString.prefix(8)
        let base = URL(fileURLWithPath: "/tmp/riptide-svc-rt-\(token)", isDirectory: true)
        let systemRoot = base.appendingPathComponent("SystemRoot", isDirectory: true)
        let userRoot = base.appendingPathComponent("UserRoot", isDirectory: true)
        let mihomoDir = userRoot.appendingPathComponent("mihomo", isDirectory: true)
        try FileManager.default.createDirectory(at: mihomoDir, withIntermediateDirectories: true)
        let config = mihomoDir.appendingPathComponent("config.yaml")
        try "mixed-port: 6152\n".write(to: config, atomically: true, encoding: .utf8)

        let supervisor = MihomoServiceSupervisor(
            systemRoot: systemRoot,
            userRoots: [userRoot.path],
            coreLogURL: base.appendingPathComponent("core.log")
        )
        let socket = URL(fileURLWithPath: "/tmp/riptide-svc-rt-\(token).sock")
        let server = UnixHTTPServer(socketPath: socket.path) { request in
            await Self.route(request, supervisor: supervisor)
        }
        try server.start()
        let client = MihomoServiceClient(socketPath: socket.path, timeoutSeconds: 5)
        return (client, supervisor, systemRoot, userRoot, config, { server.stop() })
    }

    /// Mirrors the daemon executable's routing table.
    static func route(
        _ request: UnixHTTPRequest,
        supervisor: MihomoServiceSupervisor
    ) async -> UnixHTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .json(MihomoServiceProtocol.Health())
        case ("POST", "/v1/start"):
            guard let body = try? request.decodeBody(MihomoServiceProtocol.StartRequest.self) else {
                return .error("invalid start request body", status: 400)
            }
            do {
                return .json(try await supervisor.start(request: body))
            } catch let error as MihomoServiceSupervisorError {
                return Self.supervisorError(error)
            } catch {
                return .error(error.localizedDescription, status: 500)
            }
        case ("POST", "/v1/stop"):
            do {
                return .json(try await supervisor.stop())
            } catch let error as MihomoServiceSupervisorError {
                return Self.supervisorError(error)
            } catch {
                return .error(error.localizedDescription, status: 500)
            }
        case ("GET", "/v1/status"):
            return .json(await supervisor.status())
        case ("POST", "/v1/core/install"):
            guard let body = try? request.decodeBody(MihomoServiceProtocol.CoreInstallRequest.self) else {
                return .error("invalid core install request body", status: 400)
            }
            do {
                return .json(try await supervisor.installCore(request: body))
            } catch let error as MihomoServiceSupervisorError {
                return Self.supervisorError(error)
            } catch {
                return .error(error.localizedDescription, status: 500)
            }
        default:
            return .error("not found", status: 404)
        }
    }

    private static func supervisorError(_ error: MihomoServiceSupervisorError) -> UnixHTTPResponse {
        switch error {
        case .alreadyRunning: return .error("core already running", status: 409)
        case .notRunning: return .error("core not running", status: 409)
        case .corePathNotAllowed(let path): return .error("core path not allowed: \(path)", status: 403)
        case .configPathNotAllowed(let path): return .error("config path not allowed: \(path)", status: 403)
        case .coreSourceNotAllowed(let path): return .error("core source not allowed: \(path)", status: 403)
        case .launchFailed(let detail): return .error("launch failed: \(detail)", status: 500)
        case .terminationFailed(let detail): return .error("termination failed: \(detail)", status: 500)
        case .coreInstallFailed(let detail): return .error("core install failed: \(detail)", status: 500)
        }
    }

    @Test("health, install, start, status, stop sequence over the socket")
    func fullSequence() async throws {
        let env = try bootDaemon()
        defer { env.stop() }

        let health = try await env.client.health()
        #expect(health.status == "ok")
        #expect(health.version == MihomoServiceProtocol.version)

        #expect(await env.client.ping())

        let stub = try makeStubCore(parent: env.userRoot.appendingPathComponent("downloads"))
        let install = try await env.client.installCore(sourcePath: stub.path)
        #expect(install.copied)

        let started = try await env.client.start(
            corePath: install.targetPath,
            configPath: env.config.path
        )
        #expect(started.running)

        let status = try await env.client.status()
        #expect(status.running)
        #expect(status.pid == started.pid)

        let stopped = try await env.client.stop()
        #expect(!stopped.running)
    }

    @Test("server error responses surface as typed client errors")
    func errorMapping() async throws {
        let env = try bootDaemon()
        defer { env.stop() }

        // Stop while idle → 409 mapped to a server error.
        do {
            _ = try await env.client.stop()
            Issue.record("expected server error")
        } catch let error as MihomoServiceClientError {
            guard case .server(let status, let message) = error else {
                Issue.record("unexpected error shape: \(error)")
                return
            }
            #expect(status == 409)
            #expect(message.contains("not running"))
        }
    }

    @Test("ping is false when no daemon listens")
    func pingAbsentDaemon() async {
        let client = MihomoServiceClient(
            socketPath: "/tmp/riptide-absent-\(UUID().uuidString).sock",
            timeoutSeconds: 1
        )
        #expect(await client.ping() == false)
    }
}

// MARK: - Installer script shapes

/// Records the privileged scripts an installer would run as root.
private actor ServiceScriptRecorder {
    private(set) var scripts: [String] = []
    func record(_ script: String) { scripts.append(script) }
    var last: String? { scripts.last }
}

@Suite("Mihomo service installer")
struct MihomoServiceInstallerTests {

    private func makeInstaller() throws -> (installer: MihomoServiceInstaller,
                                            support: URL,
                                            launchDaemons: URL,
                                            recorder: ServiceScriptRecorder) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-svc-inst-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let launchDaemons = root.appendingPathComponent("LaunchDaemons", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDaemons, withIntermediateDirectories: true)

        let recorder = ServiceScriptRecorder()
        let installer = MihomoServiceInstaller(
            supportDir: support,
            launchDaemonsDir: launchDaemons,
            uid: 501,
            privilegedRunner: { script in await recorder.record(script) }
        )
        return (installer, support, launchDaemons, recorder)
    }

    @Test("install builds a privileged script that bootstraps an always-on daemon")
    func installScriptShape() async throws {
        let env = try makeInstaller()
        let binary = env.support.appendingPathComponent("source-service")
        FileManager.default.createFile(atPath: binary.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        try await env.installer.install(binarySource: binary)

        let script = try #require(await env.recorder.last)
        // Copies the daemon binary and makes it executable.
        #expect(script.contains("cp \"\(binary.path)\""))
        #expect(script.contains("chmod 755"))
        // Records the installing user so the daemon can gate the socket.
        #expect(script.contains("printf '%s' '501'"))
        // Bootstraps the launchd daemon.
        #expect(script.contains("launchctl bootstrap system"))
        #expect(script.contains(MihomoServicePaths.serviceLabel))
    }

    @Test("install rejects a missing daemon binary")
    func installRejectsMissingBinary() async throws {
        let env = try makeInstaller()
        let missing = env.support.appendingPathComponent("nope")
        await #expect(throws: MihomoServiceInstaller.InstallerError.binaryNotFound) {
            try await env.installer.install(binarySource: missing)
        }
    }

    @Test("uninstall builds a script that boots out the daemon and removes its files")
    func uninstallScriptShape() async throws {
        let env = try makeInstaller()
        try await env.installer.uninstall()
        let script = try #require(await env.recorder.last)
        #expect(script.contains("launchctl bootout system/\(MihomoServicePaths.serviceLabel)"))
        #expect(script.contains("riptide-mihomo-service"))
        #expect(script.contains("mihomo-service.owner"))
        #expect(script.contains("mihomo-service.sock"))
    }

    @Test("plist pins the daemon binary and stays always-on")
    func plistShape() {
        let xml = MihomoServiceInstaller.plistXML(
            label: MihomoServicePaths.serviceLabel,
            binary: "/Library/Application Support/Riptide/riptide-mihomo-service",
            log: "/Library/Application Support/Riptide/logs/mihomo-service.log"
        )
        #expect(xml.contains("<string>\(MihomoServicePaths.serviceLabel)</string>"))
        #expect(xml.contains("<string>/Library/Application Support/Riptide/riptide-mihomo-service</string>"))
        #expect(xml.contains("<key>RunAtLoad</key>"))
        #expect(xml.contains("<key>KeepAlive</key>"))
        #expect(xml.contains("<true/>"))
    }
}

// MARK: - Launch strategy

@Suite("Mihomo launch strategy ordering")
struct MihomoLaunchStrategyTests {

    @Test("service mode wins when the daemon is reachable")
    func serviceFirst() {
        #expect(MihomoRuntimeManager.resolveLaunchStrategy(serviceAvailable: true, helperInstalled: true) == .service)
        #expect(MihomoRuntimeManager.resolveLaunchStrategy(serviceAvailable: true, helperInstalled: false) == .service)
    }

    @Test("helper is preferred over sudo when the service is absent")
    func helperBeforeSudo() {
        #expect(MihomoRuntimeManager.resolveLaunchStrategy(serviceAvailable: false, helperInstalled: true) == .helper)
        #expect(MihomoRuntimeManager.resolveLaunchStrategy(serviceAvailable: false, helperInstalled: false) == .sudo)
    }
}
