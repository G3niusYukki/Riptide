# Riptide macOS 1.0 Daily-Use Spec

## Goal

Deliver a macOS-only `1.0` release of Riptide that is stable enough for daily personal use. The release should prioritize reliable traffic capture, understandable behavior, clear diagnostics, and a coherent desktop workflow over maximal protocol breadth or full Clash Verge Rev parity.

## Product Positioning

Riptide `1.0` is not a full-featured Clash Verge Rev replacement. It is a native Swift/macOS proxy client built around the existing Riptide core, with two supported operating modes:

- `System Proxy` mode for low-risk, broadly compatible daily usage
- `TUN` mode for deeper system integration and broader traffic capture

The product target is an advanced macOS user who wants a native client with strong visibility into routing, connection state, and failure reasons.

## Success Criteria

### User Outcomes

- A user can import a local config or subscription and start the client without using the CLI.
- A user can switch between `System Proxy` and `TUN` modes from the app.
- A user can choose a node or proxy group and understand which route is being used.
- A user can inspect logs, connection state, and traffic counters when something goes wrong.
- The daily-use traffic matrix can be proxied successfully in both supported modes by the time `1.0` ships.

### Technical Outcomes

- The same core runtime powers CLI, app, system proxy mode, and TUN mode.
- Runtime state, lifecycle events, connection metadata, and error events flow through one unified control surface.
- Unsupported configuration fields are surfaced explicitly instead of being silently ignored.
- Core policy decisions remain deterministic and testable.

## Non-Goals For 1.0

- Windows, Linux, or mobile support
- Full Clash Verge Rev rule, protocol, and GUI feature parity
- `TUIC`, `WireGuard`, `MASQUE`, `MITM`, `WebDAV`, or script-engine completion
- A highly themed or heavily customized UI
- Large-scale protocol experimentation that destabilizes the daily-use baseline
- split tunneling or per-app VPN routing
- external-controller expansion beyond what is needed for app diagnostics
- advanced profile editing, profile merge tooling, or cloud sync

## Supported Capability Set For 1.0

### Required Runtime Modes

- `System Proxy` mode
- `TUN` mode
- Explicit mode switching with clear degraded-state handling if one mode is temporarily unavailable during development or beta testing

For `1.0`, both modes are release-blocking. `System Proxy` is the fallback path for alpha and beta risk management, but `1.0` is not considered complete unless both `System Proxy` and `TUN` meet the release criteria.

### Required Core Data Plane

- Stable `HTTP CONNECT`, `SOCKS5`, and `Shadowsocks` proxy paths
- Existing DNS stack extended with:
  - nameserver policy selection
  - fallback resolution path
  - respect-rules mode
- Proxy-group runtime with:
  - `Select`
  - `URL-Test`
  - `Fallback`

### Required App Experience

- Menu bar entry with quick start/stop and mode switch
- Main window with:
  - current status
  - active profile/config
  - selected node or group
  - logs
  - connection list
  - throughput counters
- Import flow for local config and subscriptions
- Manual refresh for subscriptions
- Basic multi-profile support limited to: import, list, switch active profile, and delete profile

## Architecture

### Core Principle

The app is a thin orchestration layer over the Riptide core. Core runtime behavior must stay inside `Sources/Riptide`, while `Sources/RiptideApp` owns user workflows, view state, and desktop interaction. System integration bridges such as `NetworkExtension` and system proxy management sit between those layers, but must still talk to the same runtime control surface.

### Control Surface

Introduce a single runtime-facing contract that the app, CLI, external controller, and future platform bridges all use. That contract should expose:

- lifecycle commands (`start`, `stop`, `reload`, `switch mode`)
- current runtime status
- event stream for errors, route decisions, state transitions, and counters
- connection inventory and summary statistics

This removes the current split where different entrypoints expose only fragments of runtime state.

### Runtime Ownership And IPC

Runtime ownership is mode-dependent, but the control surface is not:

- In `System Proxy` mode, the authoritative runtime lives in the app process.
- In `TUN` mode, the authoritative traffic runtime lives in the packet-tunnel extension so packet ingress, DNS policy, routing, and outbound dialing stay in the same process.
- The app remains the control-plane owner in both modes. It starts, stops, reloads, and queries runtime state through a shared control protocol.
- App ↔ extension communication should use `NETunnelProviderSession` messaging for commands plus an app-group-backed shared state store for snapshots, recent logs, counters, and connection summaries.

This design avoids cross-process hot-path networking while still giving the app a consistent view of lifecycle and diagnostics.

### Platform Distribution And Privileges

The `1.0` release target is a signed, notarized `Developer ID` macOS distribution, not a Mac App Store release. Required platform capabilities are:

- `NetworkExtension` packet tunnel entitlement
- app group for shared state and diagnostics
- standard app permissions for system proxy management where supported by macOS

Out of scope for `1.0`:

- a privileged helper daemon
- launch-at-login automation
- background enforcement beyond on-launch state reconciliation

The app may reconcile and repair stale system-proxy state on launch, but it does not attempt always-on privileged enforcement.

### Mode Architecture

`System Proxy` and `TUN` should be siblings, not separate products. Each mode is a traffic-ingress adapter over the same routing, DNS, and outbound runtime:

- `System Proxy` ingress: local proxy listener(s), system proxy registration, fast fallback
- `TUN` ingress: packet capture/forwarding via `NetworkExtension`, packet handling, route handoff into runtime

The runtime should not need to know whether traffic came from a local proxy socket or a TUN packet path after ingress normalization.

### Configuration Architecture

Configuration handling should move toward three layers:

1. raw source (`yaml`, subscription payload, URI import)
2. normalized app profile (`selected mode`, `selected group`, local app preferences)
3. executable runtime profile (`TunnelProfile`, DNS policy, group resolver, listeners)

This separation prevents UI-only state from leaking into parser logic and makes reload behavior predictable.

### Group And DNS Semantics

The `1.0` runtime uses the following semantics:

| Area | `1.0` Semantics |
|---|---|
| `Select` group | User choice persists across app restarts until profile change or explicit reset |
| `URL-Test` group | Probe on activation, manual refresh, and every 10 minutes while active |
| `Fallback` group | Use highest-priority healthy node; recover only after 2 consecutive successful probes |
| Health failure | Mark unhealthy after 3 consecutive failures or repeated latency breaches above tolerance |
| DNS authority in `System Proxy` mode | App-hosted DNS pipeline is authoritative |
| DNS authority in `TUN` mode | Extension-hosted DNS pipeline is authoritative, using the same normalized runtime profile |
| DNS fallback | Primary nameserver set first, fallback nameserver path only on timeout or hard failure |
| respect-rules | DNS request routing must consult runtime policy before selecting upstream resolver |

## Workstreams

### Workstream A: Platform And System Integration

Owns:

- `VPNTunnelManager` evolution into a real TUN bridge
- system proxy configuration and recovery behavior
- app-mode switching, entitlement-sensitive operations, and install/startup concerns

Primary risk:

- `NetworkExtension` complexity and platform-specific failure states

Fallback policy:

- `System Proxy` remains the release fallback if `TUN` is degraded

### Workstream B: Core Runtime And Networking

Owns:

- runtime control surface
- proxy-group runtime
- DNS policy extensions
- health-check integration
- selective protocol integration for post-1.0 candidates

Primary risk:

- excessive scope expansion into protocol breadth before core stability is achieved

Guardrail:

- `VMess`, `VLESS`, and `Trojan` remain post-stability scope; they do not block the base 1.0 path

### Workstream C: Desktop Product Experience

Owns:

- menu bar and main-window UX
- config/subscription workflows
- log presentation
- connection inspection
- traffic and status presentation

Primary risk:

- building UI over unstable runtime contracts

Guardrail:

- freeze event and status contracts before large UI implementation begins

## Milestones

### Milestone 0: Contract Freeze

- unify runtime status/event model
- define mode-switch semantics
- define supported configuration matrix for 1.0

Exit condition:

- all three workstreams can build against stable interfaces
- written compatibility matrix exists for supported rules, proxy types, group types, and subscription inputs

### Milestone 1: Alpha

- app can import config, start in system proxy mode, show status, logs, and counters
- the daily-use traffic matrix passes in `System Proxy` mode
- 20 clean start/stop cycles and 10 clean reload cycles complete without crash

Exit condition:

- a non-CLI user can complete import → start → browse → inspect logs → stop in `System Proxy`
- zero known `P0` crashes and no unresolved state-desync bug that blocks restart

### Milestone 2: Beta

- TUN path is functional for common traffic
- proxy groups and DNS policy extensions are live
- failure modes are observable in the app

Exit condition:

- the daily-use traffic matrix passes in both `System Proxy` and `TUN` modes
- `TUN` start/stop succeeds for 20 consecutive cycles on the primary test setup
- fallback from `TUN` failure to visible `System Proxy` recommendation is working
- zero known `P0` defects and at most 5 open `P1` defects

### Milestone 3: Release Candidate

- stability hardening
- subscription refresh and multi-profile basics
- release workflow and operational docs

Exit condition:

- 24-hour soak on the primary test machine completes without crash or stuck shutdown
- 50 clean start/stop cycles and 25 clean reload cycles complete across both modes
- zero known `P0` or `P1` defects, and at most 3 open `P2` defects
- release notes and user-facing troubleshooting docs are ready

## Daily-Use Traffic Matrix

The `1.0` release is measured against the following baseline traffic matrix:

- Safari or Chrome HTTPS browsing
- `curl` over HTTPS
- `git` over HTTPS
- Swift Package Manager dependency fetch in Xcode or `swift build`
- one long-lived app session such as chat or streaming audio/video traffic

## Error Handling

- All ingress and runtime failures must map to structured error types with a user-facing summary and a developer-facing detail payload.
- The app should distinguish between:
  - configuration errors
  - DNS failures
  - routing/policy failures
  - outbound handshake failures
  - system integration failures
- Mode failure should degrade gracefully:
  - if `TUN` cannot start, surface why and offer `System Proxy`
  - if system proxy registration fails, keep runtime state consistent and visible

## Testing Strategy

### Core

- expand unit tests around DNS policy, group selection, and runtime event emission
- add integration coverage for mode-independent routing behavior

### Platform

- isolate system-integration adapters behind protocols for test doubles
- add focused tests for mode transitions, degraded-state handling, and state recovery

### App

- verify view-model behavior for:
  - import success/failure
  - mode switching
  - connection/log updates
  - user-visible error mapping

## Release Guardrails

- Do not claim unsupported Clash compatibility.
- Do not silently accept unsupported config fields without diagnostics.
- Do not block 1.0 on niche protocols.
- Keep all new features aligned with the daily-use macOS goal.
