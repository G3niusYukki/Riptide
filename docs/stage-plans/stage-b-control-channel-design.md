# Riptide Stage B - Control Channel Integration Shell

## Goal

Provide an app↔tunnel control channel abstraction that mirrors future XPC semantics while remaining package-testable today.

## Scope

1. Define control commands (`start`, `stop`, `update`, `status`).
2. Implement in-process control channel adapter over `TunnelLifecycleManager`.
3. Add event stream for status snapshots and error events.
4. Wire CLI command path to optionally use the control channel API.

## Non-goals

- Real XPC transport.
- NEPacketTunnelProvider target plumbing.
- Entitlements/system-extension installation workflow.

## API design

### Commands

- `TunnelControlCommand.start(profile)`
- `TunnelControlCommand.stop`
- `TunnelControlCommand.update(profile)`
- `TunnelControlCommand.status`

### Responses

- `TunnelControlResponse.ack`
- `TunnelControlResponse.status(snapshot)`
- `TunnelControlResponse.error(message)`

### Event stream

- `TunnelControlEvent.statusChanged(snapshot)`
- `TunnelControlEvent.error(message)`

## Implementation

- `InProcessTunnelControlChannel` actor:
  - owns lifecycle manager
  - handles command dispatch
  - publishes events via `AsyncStream<TunnelControlEvent>`

## Testing

- command dispatch correctness
- event emission on start/stop/update/status
- error response propagation when lifecycle operation fails
