# Riptide - Sub-project 1 Phase 5: UI + Config Workflow

## Overview

Phase 4 delivered tunnel lifecycle shell.  
Phase 5 introduces app-facing workflow primitives: config import validation, runtime stats pipeline, and minimal view models suitable for SwiftUI binding.

## Goals

- Add config import service with strict validation and clear result model.
- Add runtime stats pipeline that maps tunnel status snapshots to UI-friendly state.
- Provide minimal app view models:
  - control actions (start/stop/update config)
  - status presentation fields
- Keep implementation package-safe and testable without launching UI app targets.

## Non-goals

- Full SwiftUI app target and menu bar integration
- Rich settings and node selector UX
- Persistent storage

## Architecture

### Config workflow

`ConfigImportService`:
1. Accept raw YAML string + profile name.
2. Parse via existing `ClashConfigParser`.
3. Return typed import result with parsed profile metadata.

### Stats workflow

`RuntimeStatsPipeline`:
- consumes `TunnelStatusSnapshot`
- emits `RuntimeStatsViewState` with formatted flags/counters

### View models

`TunnelControlViewModel`:
- owns lifecycle manager and current profile
- exposes `start/stop/importConfig/applyImportedProfile`

`TunnelStatusViewModel`:
- binds to `RuntimeStatsPipeline`
- exposes simple read-only state for UI rendering

## Error handling

- Config parse errors surfaced as structured import failure.
- Lifecycle operation failures surfaced directly from manager.
- No fallback to stale profile on failed import.

## Testing strategy

- Unit tests:
  - config import success/failure paths
  - stats pipeline mapping
  - control view model start/stop using mock runtime manager context

## Deliverables

- `Sources/Riptide/AppShell/` workflow services + view models
- `Tests/RiptideTests/AppShellWorkflowTests.swift`

## Phase completion outcome

By end of phase 5, sub-project 1 package-level foundation includes:
- parsing
- rules
- protocol framing
- transport orchestration
- tunnel lifecycle shell
- app-facing config + status workflow models
