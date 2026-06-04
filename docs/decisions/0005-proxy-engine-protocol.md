# ADR-0005: ProxyEngine protocol & EngineRouter default-mihomo policy

> **Status:** Accepted · **Date:** 2026-06-04 · **Deciders:** maintainers

## Context

Riptide macOS supports two proxy engines: the pure-Swift in-process
engine and the mihomo sidecar. The decision to use which engine for
which protocol was previously scattered across `MihomoConfigGenerator`
calls. As we add sing-box (for Reality, AnyTLS, WireGuard), we need a
single routing policy.

## Decision

Define `ProxyEngine` protocol and `EngineRouter` with explicit
`Policy.defaultMihomo` initial state. Per-`ProxyKind` rules:

| ProxyKind | Engine |
|-----------|--------|
| shadowsocks, vmess, vless (non-Reality), trojan, hysteria2, snell, tuic, socks5, httpConnect | mihomo |
| reality, anytls | singbox |
| any unknown kind | mihomo (fallback) |

The Swift Engine is orthogonal — it is a separate code path in
`LocalHTTPConnectProxyServer` and not routed through `EngineRouter`.

## Consequences

- New protocols are routed explicitly, not by which sidecar happens
  to support them.
- `EngineRouter.engine(for:)` is pure and fully unit-testable.
- Future engines (e.g., a hypothetical Rust core) plug in by adding
  a case to `ProxyEngineKind` and a routing rule.
