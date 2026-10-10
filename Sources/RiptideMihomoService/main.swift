import Foundation
import Riptide

// riptide-mihomo-service — the privileged launchd daemon behind Riptide's
// mihomo service mode. Mirrors Clash Verge's `clash-verge-service`: an HTTP
// IPC server on a Unix domain socket that supervises the mihomo core as
// root, so the GUI can start/stop TUN without further password prompts.
//
// Routes:
//   GET  /health           liveness + protocol version
//   POST /v1/start         launch the core (validated paths)
//   POST /v1/stop          terminate the core
//   GET  /v1/status        core snapshot
//   POST /v1/core/install  copy a core binary into the system root

// MARK: - Owner gate

/// Reads the installing user's UID recorded by `MihomoServiceInstaller`.
/// When the owner file is missing, only root may talk to the daemon
/// (fail closed).
func readAllowedOwnerUID() -> (uid: UInt32, home: String)? {
    let ownerData = try? String(contentsOf: MihomoServicePaths.ownerFileURL, encoding: .utf8)
    guard let ownerText = ownerData,
          let owner = UInt32(ownerText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return nil
    }
    guard let passwordEntry = getpwuid(owner) else { return nil }
    let home = String(cString: passwordEntry.pointee.pw_dir)
    guard !home.isEmpty, home != "/var/empty" else { return nil }
    return (owner, home)
}

// MARK: - Wiring

let allowedOwner = readAllowedOwnerUID()
let supervisor = MihomoServiceSupervisor(
    systemRoot: MihomoServicePaths.systemRoot,
    userRoots: allowedOwner.map { owner in
        [owner.home + "/Library/Application Support/Riptide"]
    } ?? []
)

let peerAcceptor: UnixHTTPServer.PeerAcceptor = { peerUID in
    if peerUID == 0 { return true }
    guard let allowedOwner else { return false }
    return peerUID == allowedOwner.uid
}

let server = UnixHTTPServer(
    socketPath: MihomoServicePaths.socketPath,
    peerAcceptor: peerAcceptor
) { request in
    await route(request: request, supervisor: supervisor)
}

func route(
    request: UnixHTTPRequest,
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
            return supervisorErrorResponse(error)
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    case ("POST", "/v1/stop"):
        do {
            return .json(try await supervisor.stop())
        } catch let error as MihomoServiceSupervisorError {
            return supervisorErrorResponse(error)
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
            return supervisorErrorResponse(error)
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    default:
        return .error("not found", status: 404)
    }
}

func supervisorErrorResponse(_ error: MihomoServiceSupervisorError) -> UnixHTTPResponse {
    switch error {
    case .alreadyRunning:
        return .error("core already running", status: 409)
    case .notRunning:
        return .error("core not running", status: 409)
    case .corePathNotAllowed(let path):
        return .error("core path not allowed: \(path)", status: 403)
    case .configPathNotAllowed(let path):
        return .error("config path not allowed: \(path)", status: 403)
    case .coreSourceNotAllowed(let path):
        return .error("core source not allowed: \(path)", status: 403)
    case .launchFailed(let detail):
        return .error("launch failed: \(detail)", status: 500)
    case .terminationFailed(let detail):
        return .error("termination failed: \(detail)", status: 500)
    case .coreInstallFailed(let detail):
        return .error("core install failed: \(detail)", status: 500)
    }
}

// MARK: - Lifecycle

func shutdown() {
    // Teardown is async (actor hops); the supervisor caps itself at ~5.5s,
    // so bound the wait at 8s and exit regardless.
    Task {
        server.stop()
        _ = try? await supervisor.stop()
        exit(0)
    }
    Thread.sleep(forTimeInterval: 8)
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signalSource.setEventHandler { shutdown() }
signalSource.resume()
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler { shutdown() }
interruptSource.resume()

do {
    try server.start()
    print("[riptide-mihomo-service] listening on \(MihomoServicePaths.socketPath)")
} catch {
    print("[riptide-mihomo-service] failed to start: \(error)")
    exit(1)
}

RunLoop.main.run()
