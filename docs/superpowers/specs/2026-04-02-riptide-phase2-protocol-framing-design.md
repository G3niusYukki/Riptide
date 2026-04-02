# Riptide - Sub-project 1 Phase 2: Protocol Framing Layer

## Overview

Phase 1 delivered config parsing and rule matching.  
Phase 2 introduces a protocol framing layer that makes outbound proxy protocols concrete and testable before tunnel I/O integration.

## Goals

- Define unified outbound proxy interfaces for TCP-based forwarding.
- Implement deterministic request framing for:
  - HTTP CONNECT
  - SOCKS5 CONNECT (no auth)
  - Shadowsocks target-address preamble encoding
- Keep this phase transport-agnostic: generate bytes and parse protocol responses without opening sockets.

## Non-goals

- Real network dial/connect lifecycle
- UDP relay and UDP ASSOCIATE
- VMess/VLESS and proxy groups
- PacketTunnelProvider integration

## Architecture

### Core abstraction

```swift
public protocol OutboundProxyProtocol {
    func makeConnectRequest(for target: ConnectionTarget) throws -> [Data]
    func parseConnectResponse(_ data: Data) throws -> ConnectResponse
}
```

- `makeConnectRequest` returns one or more frames to send in order.
- `parseConnectResponse` validates server response and returns semantic outcome.

### Shared models

- `ConnectionTarget`: host + port + host classification
- `ConnectResponse`: success/failure + optional diagnostic reason
- `ProtocolError`: invalid target, unsupported auth mode, malformed response, rejected by upstream

### Implementations

1. `HTTPConnectProtocol`
   - Build `CONNECT host:port HTTP/1.1` request
   - Include `Host` header
   - Accept any `2xx` status as success
2. `SOCKS5Protocol`
   - Generate greeting: version 5, one method, no-auth
   - Generate connect request with domain/IPv4/IPv6 address types
   - Parse method selection and connect reply
3. `ShadowsocksProtocol`
   - Build target address preamble (`ATYP + DST.ADDR + DST.PORT`) per SOCKS5-style address encoding
   - Crypto and stream encryption remain out of scope in this phase

## Data flow

1. Rule engine selects proxy node.
2. Node type maps to protocol implementation.
3. Protocol implementation creates connect frames for target.
4. Transport layer (future phase) sends frames and provides response bytes.
5. Protocol parser returns connection result.

## Error handling

- Invalid host/port or malformed response throws typed protocol errors.
- Protocol-level reject responses map to explicit rejection reasons.
- No silent fallback to direct route in protocol layer.

## Testing strategy

- Unit tests only:
  - HTTP CONNECT byte output and status parsing
  - SOCKS5 greeting/connect framing and response parsing
  - Shadowsocks address preamble encoding for domain and IPv4
- Golden-byte assertions to avoid accidental framing drift.

## Deliverables

- `Sources/Riptide/Protocols/` module with interfaces and three protocol implementations
- `Tests/RiptideTests/` protocol framing tests
- No runtime socket dependency in this phase

## Next after Phase 2

Phase 3 focuses on transport integration:
- async connection adapters
- connection pool
- protocol + transport orchestration entrypoint for tunnel-side integration
