# Riptide - Sub-project 1 Phase 3: Transport Integration

## Overview

Phase 2 introduced protocol framing/parsing without I/O.  
Phase 3 wires protocols to an abstract transport session so connect flows can run end-to-end in tests and later map cleanly to real sockets.

## Goals

- Define asynchronous transport abstractions for bidirectional byte exchange.
- Add lightweight connection pool primitives to manage reusable sessions.
- Build a proxy orchestrator that executes protocol handshakes over transport:
  - HTTP CONNECT (single request/response)
  - SOCKS5 (method selection + connect request/reply)
  - Shadowsocks (preamble send only in this phase)
- Keep implementation deterministic and fully unit-testable with mocks.

## Non-goals

- Real Network.framework/SwiftNIO socket dialing
- Packet tunnel integration
- TLS, authentication expansion, retry policy
- UDP and advanced pooling policy

## Architecture

### Transport contracts

```swift
protocol TransportSession {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

protocol TransportDialer {
    func openSession(to node: ProxyNode) async throws -> TransportSession
}
```

### Pool primitives

- `PooledTransportConnection`: wraps node + session + lifecycle flags.
- `TransportConnectionPool`:
  - acquire by `ProxyNode`
  - release connection for reuse
  - optional close/remove on fatal handshake failure
- Initial policy: one reusable connection per node key (simple and safe for phase 3).

### Proxy orchestration

`ProxyConnector` responsibilities:

1. Acquire/open transport session for selected node.
2. Select protocol implementation by node kind.
3. Execute handshake sequence:
   - HTTP: send connect frame → receive response → parse
   - SOCKS5: send greeting → receive method selection → parse; send connect frame → receive reply → parse
   - Shadowsocks: send preamble (no response required for success in phase 3)
4. Return an active connected context (node + session) on success.
5. Close and surface typed errors on failure.

## Error handling

- Keep explicit failures, no silent fallback:
  - dial failures bubble up
  - malformed protocol responses throw `ProtocolError`
  - failed handshake closes session before returning error
- Pool only stores healthy sessions.

## Testing strategy

- Add mock transport session and dialer:
  - programmable receive queue
  - captured outbound frames
  - close tracking
- Tests:
  - pool acquire/release reuses session for same node
  - HTTP connect flow sends expected frame and parses success
  - SOCKS5 flow sends two-step handshake frames in order
  - failed SOCKS5 auth response propagates error and closes session
  - Shadowsocks flow sends encoded preamble once

## Deliverables

- `Sources/Riptide/Transport/` for session/dialer/pool contracts
- `Sources/Riptide/Connection/ProxyConnector.swift` for orchestration
- `Tests/RiptideTests/` integration-style unit tests using mocks

## Next after Phase 3

Phase 4 will map transport contracts to real tunnel runtime surfaces:
- PacketTunnelProvider scaffold
- lifecycle management between app and tunnel targets
- status/statistics plumbing
