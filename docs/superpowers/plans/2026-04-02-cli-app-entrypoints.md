# CLI and App Entrypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runnable CLI and minimal SwiftUI app executables on top of the existing Riptide package modules.

**Architecture:** Keep entrypoints thin by reusing current package services (`ConfigImportService`, `TunnelLifecycleManager`, app-shell workflow types). Introduce a CLI target using ArgumentParser and an App target using SwiftUI. Provide mock runtime wiring in entrypoint targets only, without changing core library behavior.

**Tech Stack:** Swift 6.2, Swift Package Manager, swift-argument-parser, SwiftUI

---

### Task 1: Add executable targets and dependencies

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add failing build context for missing executable targets**

Run: `swift build --product riptide`  
Expected: FAIL (product not found)

- [ ] **Step 2: Add package dependency and new executable products**

Update `Package.swift`:
- add dependency: `https://github.com/apple/swift-argument-parser` (from `1.5.0`)
- add product: `.executable(name: "riptide", targets: ["RiptideCLI"])`
- add product: `.executable(name: "RiptideApp", targets: ["RiptideApp"])`
- add targets:
  - `RiptideCLI` depends on `Riptide` + `ArgumentParser`
  - `RiptideApp` depends on `Riptide`

- [ ] **Step 3: Resolve dependencies**

Run: `swift package resolve`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add CLI and app executable targets"
```

### Task 2: Implement CLI entrypoint

**Files:**
- Create: `Sources/RiptideCLI/main.swift`
- Create: `Sources/RiptideCLI/CLIMockTunnelRuntime.swift`
- Test: `Tests/RiptideTests/CLICommandTests.swift`

- [ ] **Step 1: Write failing CLI command tests**

Add tests for:
- validate command success with valid yaml
- validate command failure with invalid yaml
- run command startup path returns running state text

- [ ] **Step 2: Run targeted tests to verify failure**

Run: `swift test --filter CLICommandTests`  
Expected: FAIL (symbols/commands missing)

- [ ] **Step 3: Implement minimal CLI commands**

In `main.swift` implement:
- root command `riptide`
- `validate --config`
- `run --config`
- shared file loading helper

In `CLIMockTunnelRuntime.swift` implement test-friendly runtime conforming to `TunnelRuntime`.

- [ ] **Step 4: Run targeted tests**

Run: `swift test --filter CLICommandTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/RiptideCLI Tests/RiptideTests/CLICommandTests.swift
git commit -m "feat: add riptide CLI entrypoint"
```

### Task 3: Implement App entrypoint

**Files:**
- Create: `Sources/RiptideApp/RiptideApp.swift`
- Create: `Sources/RiptideApp/AppViewModel.swift`
- Create: `Sources/RiptideApp/CLIMockTunnelRuntime.swift` (or shared app runtime file)

- [ ] **Step 1: Add minimal SwiftUI app structure**

Create `@main` app that renders:
- title
- start button
- stop button
- status text

- [ ] **Step 2: Add app view model using existing package services**

`AppViewModel` should:
- hold `TunnelControlViewModel`
- create demo YAML and import+start
- stop lifecycle
- refresh status snapshot for display

- [ ] **Step 3: Build app product**

Run: `swift build --product RiptideApp`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/RiptideApp
git commit -m "feat: add minimal SwiftUI app entrypoint"
```

### Task 4: End-to-end verification and docs sync

**Files:**
- Modify: `/Users/peterzhang/.copilot/session-state/a8f66b17-7a1a-4d77-815d-f5662200d0a6/plan.md`
- Optional Modify: relevant spec note files if behavior changed

- [ ] **Step 1: Run full suite and build both executables**

Run:
- `swift test`
- `swift build --product riptide`
- `swift build --product RiptideApp`

Expected: all PASS

- [ ] **Step 2: Update session plan status**

Record that project now includes executable CLI and app entrypoint.

- [ ] **Step 3: Final commit and push**

```bash
git add .
git commit -m "feat: add executable entrypoints for CLI and app"
git push
```
