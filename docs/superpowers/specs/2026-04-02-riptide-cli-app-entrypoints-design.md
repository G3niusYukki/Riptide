# Riptide - CLI and App Entrypoints Design

## Overview

Current project is a Swift Package library without executable entrypoints.  
This design adds:

1. A CLI executable target (`riptide`) for config validation and tunnel lifecycle simulation.
2. A minimal App executable target (`RiptideApp`) with SwiftUI window and status display backed by existing package modules.

## Goals

- Preserve existing library architecture and tests.
- Add zero-breaking executable surfaces.
- Keep entrypoints thin and reuse `ConfigImportService`, `TunnelLifecycleManager`, and app-shell models.

## Non-goals

- Full production NetworkExtension integration.
- Complex GUI features (node management, rule editor, dashboards).
- Daemonized tunnel runtime.

## CLI Entrypoint

Command shape:

- `riptide validate --config <path>`
  - parse YAML using `ConfigImportService`
  - print summary (mode, proxy count, rule count)
- `riptide run --config <path>`
  - load profile
  - start mock tunnel lifecycle
  - print running state snapshot

Implementation notes:

- use `ArgumentParser` package dependency
- add `RiptideCLI` executable target
- provide a simple mock runtime implementation in CLI target only

## App Entrypoint

Minimal SwiftUI app:

- window with:
  - app title
  - “Load Demo Config & Start” button
  - “Stop” button
  - current lifecycle state and counters text

Implementation notes:

- add executable target `RiptideApp`
- use `@main` SwiftUI app entry
- use a lightweight observable adapter over `TunnelControlViewModel`
- generate a small in-memory demo YAML profile for start flow (no file picker in this phase)

## Testing

- keep existing unit tests intact
- add CLI parser/command behavior tests where feasible in package tests
- App target compile validation via `swift build`

## Deliverables

- `Package.swift` updated with executables and dependencies
- `Sources/RiptideCLI/*`
- `Sources/RiptideApp/*`
- optional CLI-focused tests in `Tests/RiptideTests/*`
