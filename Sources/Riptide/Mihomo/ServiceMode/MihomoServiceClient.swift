import Foundation

/// Errors raised by `MihomoServiceClient`.
public enum MihomoServiceClientError: Error, Equatable, Sendable {
    /// The daemon socket is unreachable (not installed / not running).
    case serviceUnavailable
    /// The daemon replied with a non-2xx status.
    case server(Int, String)
    /// The daemon replied with a malformed body.
    case malformedResponse
}

/// App-side client for the privileged `riptide-mihomo-service` daemon.
///
/// Speaks the daemon's HTTP-over-Unix-socket protocol (the counterpart of
/// Clash Verge's GUI-side service client):
///
/// - `GET  /health`          — daemon liveness + protocol version
/// - `POST /v1/start`        — launch the mihomo core as root
/// - `POST /v1/stop`         — terminate the core
/// - `GET  /v1/status`       — core running/pid/uptime snapshot
/// - `POST /v1/core/install` — copy a core binary into the system root
public actor MihomoServiceClient {

    private let socketPath: String
    private let timeoutSeconds: UInt32

    /// - Parameters:
    ///   - socketPath: daemon socket path (default
    ///     `/Library/Application Support/Riptide/mihomo-service.sock`).
    ///   - timeoutSeconds: per-request socket timeout.
    public init(
        socketPath: String = MihomoServicePaths.socketPath,
        timeoutSeconds: UInt32 = 5
    ) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    /// True when the daemon answers `GET /health`. Never throws; suitable
    /// for launch-strategy probing.
    public func ping() -> Bool {
        let client = UnixHTTPClient(socketPath: socketPath, timeoutSeconds: 2)
        let request = UnixHTTPRequest(method: "GET", path: "/health")
        guard let response = try? client.send(request) else { return false }
        return (200..<300).contains(response.status)
    }

    /// Fetches daemon health, including its protocol version.
    public func health() throws -> MihomoServiceProtocol.Health {
        try roundTrip(request: UnixHTTPRequest(method: "GET", path: "/health"))
    }

    /// Asks the daemon to launch the core.
    /// - Returns: the post-launch status.
    public func start(
        corePath: String,
        configPath: String,
        environment: [String: String] = [:]
    ) throws -> MihomoServiceProtocol.Status {
        let body = MihomoServiceProtocol.StartRequest(
            corePath: corePath,
            configPath: configPath,
            environment: environment
        )
        let request = try post(path: "/v1/start", body: body)
        return try roundTrip(request: request)
    }

    /// Asks the daemon to terminate the core.
    /// - Returns: the post-stop (idle) status.
    public func stop() throws -> MihomoServiceProtocol.Status {
        try roundTrip(request: UnixHTTPRequest(method: "POST", path: "/v1/stop"))
    }

    /// Fetches the supervised core's status snapshot.
    public func status() throws -> MihomoServiceProtocol.Status {
        try roundTrip(request: UnixHTTPRequest(method: "GET", path: "/v1/status"))
    }

    /// Asks the daemon (as root) to install a core binary into the system
    /// root. Idempotent: an identical existing installation is skipped.
    public func installCore(
        sourcePath: String,
        force: Bool = false
    ) throws -> MihomoServiceProtocol.CoreInstallResponse {
        let body = MihomoServiceProtocol.CoreInstallRequest(sourcePath: sourcePath, force: force)
        let request = try post(path: "/v1/core/install", body: body)
        return try roundTrip(request: request)
    }

    // MARK: - Private

    private func post<T: Encodable>(path: String, body: T) throws -> UnixHTTPRequest {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw MihomoServiceClientError.malformedResponse
        }
        return UnixHTTPRequest(
            method: "POST",
            path: path,
            headers: ["content-type": "application/json"],
            body: data
        )
    }

    private func roundTrip<T: Decodable>(request: UnixHTTPRequest, type: T.Type) throws -> T {
        let response = try roundTripRaw(request: request)
        guard let decoded = try? response.decodeBody(type) else {
            throw MihomoServiceClientError.malformedResponse
        }
        return decoded
    }

    private func roundTrip<T: Decodable>(request: UnixHTTPRequest) throws -> T {
        try roundTrip(request: request, type: T.self)
    }

    private func roundTripRaw(request: UnixHTTPRequest) throws -> UnixHTTPResponse {
        let client = UnixHTTPClient(socketPath: socketPath, timeoutSeconds: timeoutSeconds)
        do {
            let response = try client.send(request)
            guard (200..<300).contains(response.status) else {
                let message = (try? response.decodeBody(MihomoServiceProtocol.ErrorResponse.self))?.error
                    ?? String(data: response.body, encoding: .utf8)
                    ?? "status \(response.status)"
                throw MihomoServiceClientError.server(response.status, message)
            }
            return response
        } catch is UnixHTTPClientError {
            throw MihomoServiceClientError.serviceUnavailable
        }
    }
}
