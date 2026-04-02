# Riptide vs Surge for Mac Gap Analysis

Date: 2026-04-02

## Summary

Riptide now has a credible engine foundation plus a real local HTTP CONNECT entrypoint, but it is still much closer to a modular proxy core than to the full Surge for Mac product.

This document uses the Surge manual as the comparison baseline:

- Components overview: https://manual.nssurge.com/overview/components.html
- Understanding Surge: https://manual.nssurge.com/book/understanding-surge/cn/understanding-surge-cn.pdf

## What Riptide already covers

- Strict Clash-style config parsing for a focused subset
- Rule routing for `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`, `GEOIP`, `MATCH/FINAL`
- Outbound protocol handshakes for HTTP CONNECT, SOCKS5, and Shadowsocks target preamble
- Live TCP runtime path for `DIRECT`, `REJECT`, and named proxy nodes
- Local HTTP CONNECT proxy server with bidirectional traffic relay
- CLI entrypoints and package-testable app shell abstractions

## Largest remaining gaps vs Surge for Mac

### 1. Traffic interception and system integration

Surge for Mac can work as a system-level network tool through system proxy integration and Enhanced Mode / Surge VIF.  
Riptide still lacks:

- `NEPacketTunnelProvider` integration
- system settings / helper install flow
- TUN or packet-level interception
- per-network environment switching

### 2. DNS subsystem

Surge includes a rich DNS stack, cache, policy-aware resolution, and advanced routing behavior.  
Riptide still lacks:

- DNS listener / resolver pipeline
- DoH / DoT / TCP / UDP DNS handling
- fake-IP and DNS cache behavior
- rule decisions enriched by DNS metadata

### 3. Advanced policy layer

Surge supports policy groups, health checks, and latency-aware selection.  
Riptide still lacks:

- proxy groups
- automatic fallback / url-test style probing
- node health state and scheduling
- user-selectable global policy in the app

### 4. Inspection and debugging

Surge ships request inspection, Dashboard, MITM, Rewrite, Script, and Map Local capabilities.  
Riptide still lacks:

- HTTPS MITM certificate pipeline
- request/response capture
- rewrite rules and local mapping
- JavaScript scripting surface
- external controller / dashboard APIs

### 5. Protocol depth and production hardening

Riptide has handshake coverage, but not full production data-path depth for every protocol.  
Key missing items:

- Shadowsocks AEAD encryption/decryption
- broader proxy type coverage
- richer error diagnostics and observability
- connection reuse and lifecycle policies tuned for long-running service mode

### 6. App completeness

Surge for Mac is a polished desktop product with operational UI and control surfaces.  
Riptide app code is still minimal and partly mock-backed:

- no real profile management UI
- no dashboard or request list
- no system integration controls
- no production runtime embedded in the app shell

## What this execution closes

This iteration focuses on the shortest path from "engine demo" to "real traffic can enter the system":

1. Honor `direct`, `global`, and `rule` mode semantics in config/runtime behavior.
2. Allow minimal direct/global configs without dummy sections.
3. Add a local HTTP CONNECT proxy server that accepts real client traffic and relays it through the live runtime.
4. Track active connections and byte counters through the relay path.
5. Add a `riptide serve` CLI command for local end-to-end usage.

## Recommended next stages

### Stage 1: System proxy and app integration

- Replace the app mock runtime with the live runtime path.
- Add importable profiles and local proxy start/stop from the app.
- Add system proxy helper flow before NetworkExtension work.

### Stage 2: DNS foundation

- Add DNS models to config parsing.
- Implement policy-aware DNS resolution and cache.
- Support baseline UDP/TCP DNS plus one encrypted DNS mode.

### Stage 3: Policy groups and health checks

- Add proxy group models and parser support.
- Implement active probing and fallback / url-test selection.
- Expose selected global policy through control channel and app.

### Stage 4: Full product path

- Packet tunnel / Enhanced Mode equivalent
- dashboard and external controller
- MITM / rewrite / scripting surfaces
- protocol hardening and production observability
