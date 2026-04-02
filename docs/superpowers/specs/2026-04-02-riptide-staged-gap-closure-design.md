# Riptide - Staged Gap Closure Plan (Based on Surge Gap Assessment)

## Context

The current codebase has strong modular architecture but still uses mocked runtime I/O paths.  
The pasted assessment identifies the key production blockers: real transport I/O, live runtime path, system integration, and crypto depth.

This plan converts those findings into executable stages while preserving existing package-first architecture.

## Stage A (This execution): make real network path runnable without NetworkExtension

### Goals

1. Add real TCP transport session/dialer implementation using `Network.framework`.
2. Add a live tunnel runtime that performs policy resolution and executes:
   - `DIRECT` → direct dial to target
   - `REJECT` → explicit runtime error
   - `Proxy Node` → existing protocol connector path
3. Extend CLI with a live smoke command for end-to-end connectivity checks.

### Non-goals in Stage A

- NEPacketTunnelProvider target integration
- Shadowsocks AEAD encryption
- DNS subsystem and Fake-IP
- XPC process split

### Deliverables

- `Sources/Riptide/Transport/*` live TCP implementations
- `Sources/Riptide/Tunnel/LiveTunnelRuntime.swift`
- CLI `smoke` command
- tests covering live-runtime behavior using test doubles

## Stage B: system integration shell

1. Add app/tunnel native targets with PacketTunnelProvider scaffold.
2. Add app↔tunnel status/update channel (initially in-process abstraction, then XPC boundary).
3. Wire lifecycle manager to actual tunnel provider control path.

## Stage C: production proxy depth

1. Shadowsocks AEAD encrypt/decrypt path
2. DNS subsystem (UDP/TCP/DoH foundation)
3. GeoIP database-backed rule matching

## Stage D: advanced feature parity trajectory

1. Proxy groups and health-check scheduling
2. request capture / rewrite / debugging surfaces
3. richer UI and observability

## Implementation strategy

- Keep strict failures; no silent fallback.
- Reuse current abstractions (`TransportDialer`, `ProxyConnector`, `TunnelRuntime`) to avoid architecture churn.
- Add small focused types instead of overloading existing mocks.
- Ensure every stage leaves a runnable, test-backed milestone.
