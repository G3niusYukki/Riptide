# AGENTS.md

## Project Summary

Riptide is a Swift proxy engine with a library-first architecture and two runnable entrypoints:

- `Riptide` — core library
- `RiptideCLI` — command-line executable
- `RiptideApp` — SwiftUI demo app

Primary concerns in this repository are strict config parsing, deterministic rule routing, protocol framing, transport orchestration, tunnel lifecycle management, and local proxy runtime behavior.

## Environment

- Target platform: macOS 14+
- Toolchain: Swift 6.2+ / Xcode 16+
- Package manager: Swift Package Manager

## Repo Layout

- `Sources/Riptide/Config` — Clash-compatible config parsing and validation
- `Sources/Riptide/Models` — core config, routing, and proxy value models
- `Sources/Riptide/Rules` — rule matching and GeoIP integration points
- `Sources/Riptide/Transport` — transport contracts, dialers, pooling, TCP/TLS/WS layers
- `Sources/Riptide/Protocols` — outbound proxy protocol framing and per-protocol streams
- `Sources/Riptide/Connection` — proxy connection orchestration
- `Sources/Riptide/Tunnel` — runtime and lifecycle management
- `Sources/Riptide/Control` — control channel and external controller surfaces
- `Sources/Riptide/LocalProxy` — local HTTP CONNECT ingress and relaying
- `Sources/Riptide/DNS` — DNS codec, cache, and pipeline
- `Sources/Riptide/AppShell` — app-facing workflow and status/view-model support
- `Sources/RiptideCLI` — CLI entrypoint and command handling
- `Sources/RiptideApp` — SwiftUI app shell
- `Tests/RiptideTests` — unit and integration-style coverage

## Build And Test

Use SwiftPM commands from the repo root:

```bash
swift build
swift test
swift test --filter "RuleEngine"
swift run riptide --help
swift run RiptideApp
```

## Architecture Notes

- Prefer strict, explicit failure behavior over silent fallback logic.
- Keep request flow aligned with the current architecture:
  `LocalHTTPConnectProxyServer` → `LiveTunnelRuntime` → `RuleEngine` → routing policy → `ProxyConnector` → transport/protocol handshake.
- Preserve the library-first split: shared logic belongs in `Sources/Riptide`, not CLI or app targets.
- Treat protocol stream implementations and transport layers as separable units with clear interfaces.

## Coding Conventions

- Follow Swift 6 strict concurrency conventions already used in the repo.
- Prefer `struct`/`enum` models with `Equatable` and `Sendable` where appropriate.
- Keep stateful runtime components isolated and concurrency-safe.
- Do not add logic to `Sources/Riptide/Riptide.swift`; it is the module entry surface.
- Avoid force unwraps and avoid introducing silent fallbacks.
- Keep changes modular and consistent with the surrounding folder’s patterns.

## Change Guidance

- Fix the root cause rather than patching symptoms when practical.
- Add or update tests for behavior changes, especially parser, routing, transport, and runtime behavior.
- Keep scaffolding and partially wired subsystems clearly separated from production-ready paths.
- Do not broaden support claims in docs or code unless the behavior is actually wired end-to-end.
- For new features, prefer dependency injection over hard-coded global behavior.

## Validation Expectations

- Run targeted tests first when changing a focused area.
- Run `swift test` before claiming the work is complete when feasible.
- If changing CLI behavior, verify the related command path with `swift run riptide ...`.
- If changing app-facing state or workflow code, sanity-check `RiptideApp` buildability when feasible.

## Documentation

- Update `README.md` when user-visible behavior, commands, or supported capabilities change.
- Keep documentation precise about what is implemented versus scaffolded.
