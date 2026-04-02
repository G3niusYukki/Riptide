# Riptide - Sub-project 1 Phase 4: Tunnel + App Shell

## Overview

Phase 3 introduced protocol+transport orchestration in package form.  
Phase 4 adds a tunnel lifecycle shell that mimics app-to-tunnel control flow while staying Swift Package compatible.

## Goals

- Define a tunnel runtime contract for start/stop/update/status.
- Implement lifecycle manager with explicit state transitions.
- Expose status snapshots suitable for future app UI binding.
- Keep all logic testable without NetworkExtension target requirements.

## Non-goals

- Real `NEPacketTunnelProvider` subclass and entitlement wiring
- XPC implementation details
- Live packet interception

## Architecture

### Runtime contract

`TunnelRuntime` abstracts a tunnel backend:
- `start(config:)`
- `stop()`
- `update(config:)`
- `status()`

### Lifecycle manager

`TunnelLifecycleManager` owns:
- current state (`stopped`, `starting`, `running`, `stopping`, `error`)
- last error message
- runtime delegation

State machine rules:
1. start: stopped → starting → running/error
2. stop: running/error → stopping → stopped
3. update: only valid in running state

### Status model

`TunnelStatusSnapshot`:
- state
- active profile name (if any)
- bytes up/down
- active connections
- last error

## Error handling

- Illegal transitions throw typed lifecycle errors.
- Runtime errors are captured into state `.error` with details.
- No hidden retries or silent state correction.

## Testing strategy

- Unit tests with mock runtime:
  - start success path
  - start failure enters error state
  - update rejected when not running
  - stop from running returns stopped
  - status reflects runtime counters

## Deliverables

- `Sources/Riptide/Tunnel/` contracts, models, lifecycle manager
- `Tests/RiptideTests/TunnelLifecycleTests.swift`

## Next after Phase 4

Phase 5 connects this shell to minimal UI workflow components:
- config import pipeline
- lightweight view models for control/status
- package-safe SwiftUI compatibility layer (when available)
