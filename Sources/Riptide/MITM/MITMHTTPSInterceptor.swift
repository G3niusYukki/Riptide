import Foundation
import Network

/// HTTPS interception for configured hosts.
/// Host matching, per-host certificate generation, and TLS termination are wired;
/// HTTP request/response inspection is still handled by downstream consumers.
public actor MITMHTTPSInterceptor {
    private let mitmManager: MITMManager
    private let verifyUpstreamCertificates: Bool

    public init(mitmManager: MITMManager, verifyUpstreamCertificates: Bool = true) {
        self.mitmManager = mitmManager
        self.verifyUpstreamCertificates = verifyUpstreamCertificates
    }

    /// Determines whether to intercept a given host:port combination.
    public func shouldIntercept(host: String, port: Int) async -> Bool {
        _ = port  // Port is not used in the current matching logic
        return await mitmManager.shouldIntercept(host)
    }

    /// Handles an intercepted HTTPS connection.
    /// If the host matches MITM rules, terminates client TLS and establishes a
    /// separate upstream TLS session before relaying decrypted application bytes.
    /// Otherwise, relays the raw TLS stream without modification.
    public func handleConnection(
        clientSession: any TransportSession,
        target: ConnectionTarget,
        upstreamSession: any TransportSession,
        connectionID: UUID,
        runtime: LiveTunnelRuntime
    ) async throws {
        let host = target.sniffedDomain ?? target.host
        let shouldInterceptHost = await shouldIntercept(host: host, port: target.port)

        guard shouldInterceptHost else {
            // Not intercepting — relay raw TLS stream
            try await relayRawTraffic(
                clientSession: clientSession,
                upstreamSession: upstreamSession,
                connectionID: connectionID,
                runtime: runtime
            )
            return
        }

        // Record interception
        await mitmManager.recordInterception(host: host, method: "CONNECT", path: "\(target.host):\(target.port)")

        let identity = try await mitmManager.serverIdentity(for: host)
        let clientTLS = try MITMTLSSession.server(over: clientSession, identity: identity)
        let upstreamTLS = try MITMTLSSession.client(
            over: upstreamSession,
            serverName: host,
            verifyServerCertificate: verifyUpstreamCertificates
        )
        let httpObserver = MITMHTTPFlowObserver(manager: mitmManager, host: host, port: target.port)

        try await relayRawTraffic(
            clientSession: clientTLS,
            upstreamSession: upstreamTLS,
            connectionID: connectionID,
            runtime: runtime,
            httpObserver: httpObserver
        )
    }

    /// Relays raw TLS traffic between client and upstream (pass-through mode).
    private func relayRawTraffic(
        clientSession: any TransportSession,
        upstreamSession: any TransportSession,
        connectionID: UUID,
        runtime: LiveTunnelRuntime,
        httpObserver: MITMHTTPFlowObserver? = nil
    ) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.pump(
                        source: clientSession,
                        sink: upstreamSession,
                        connectionID: connectionID,
                        runtime: runtime,
                        direction: .clientToUpstream,
                        httpObserver: httpObserver
                    )
                }
                group.addTask {
                    try await self.pump(
                        source: upstreamSession,
                        sink: clientSession,
                        connectionID: connectionID,
                        runtime: runtime,
                        direction: .upstreamToClient,
                        httpObserver: httpObserver
                    )
                }

                _ = try await group.next()
                await clientSession.close()
                await upstreamSession.close()
                group.cancelAll()
                while let _ = try await group.next() {}
            }
        } catch {
            await clientSession.close()
            await upstreamSession.close()
            await runtime.closeConnection(id: connectionID)
            throw error
        }

        await runtime.closeConnection(id: connectionID)
    }

    private enum PumpDirection {
        case clientToUpstream
        case upstreamToClient
    }

    private func pump(
        source: any TransportSession,
        sink: any TransportSession,
        connectionID: UUID,
        runtime: LiveTunnelRuntime,
        direction: PumpDirection,
        httpObserver: MITMHTTPFlowObserver?
    ) async throws {
        while Task.isCancelled == false {
            let data = try await source.receive()
            if data.isEmpty { return }
            if let httpObserver {
                switch direction {
                case .clientToUpstream:
                    await httpObserver.observeClientToUpstream(data)
                case .upstreamToClient:
                    await httpObserver.observeUpstreamToClient(data)
                }
            }
            try await sink.send(data)

            switch direction {
            case .clientToUpstream:
                await runtime.recordTransfer(connectionID: connectionID, bytesUp: UInt64(data.count))
            case .upstreamToClient:
                await runtime.recordTransfer(connectionID: connectionID, bytesDown: UInt64(data.count))
            }
        }
    }
}
