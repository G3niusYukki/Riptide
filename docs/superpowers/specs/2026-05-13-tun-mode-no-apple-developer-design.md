# TUN Mode Without Apple Developer — Design Spec

> **Status:** Approved
> **Date:** 2026-05-13
> **Goal:** Make Riptide fully usable in TUN mode without an Apple Developer account (no code signing, no privileged helper) and document TUN as the recommended mode for unsigned builds.

## Problem

Riptide's production readiness analysis identified these blockers for non-Developer users:

1. **README labels TUN mode "Beta"** despite the code path being complete with auto-recovery
2. **`RuntimeError.tunUnavailable`** is dead code — never thrown, but implies TUN doesn't work
3. **TUN recovery has no upper bound** — can loop infinitely on persistent failure
4. **`verifyTUNInterface()` hardcodes `utun120`** — misses dynamically-assigned utun device names
5. **`stop()` has no forceful termination fallback** — a hung mihomo process can block restart
6. **System Proxy guard silently fails** when helper is not installed — user gets no feedback
7. **Onboarding doesn't guide users** toward TUN mode when helper is absent
8. **`AppRuntime.swift`** contains demo/mock code in the production source tree
9. **`CLAUDE.md` Known Limitation #2** incorrectly claims TUN uses NetworkExtension

## Design

### Principle

TUN mode and System Proxy mode have **independent availability requirements**:

| Mode | Requires Helper | Works Unsigned | Guard |
|------|----------------|----------------|-------|
| System Proxy | Yes (for guard) | Partially (no auto-restore) | Helper-dependent |
| TUN | No | Fully | Not needed (packet-level interception) |

TUN mode uses mihomo's built-in gVisor stack to intercept all traffic at the packet level. It does NOT rely on macOS system proxy settings, so the system proxy guard is irrelevant in TUN mode. This makes TUN the natural primary mode for unsigned builds.

### Changes

#### 1. Remove TUN Beta Labeling

- **`Sources/Riptide/Mihomo/MihomoRuntimeManager.swift:19-20`**: Delete `case tunUnavailable(String)` from `RuntimeError` enum
- **`README.md:144-148`**: Change TUN row status from `Beta` to `Stable`, update description
- **`README.md:29-36`**: Add note that TUN is recommended for unsigned builds
- **`README.md:168`**: Add guidance to select TUN after quaratine removal

#### 2. TUN Recovery Hardening

- **`MihomoRuntimeManager.swift:383-395`**: Wrap `attemptTUNRecovery()` with max-retry counter (3 attempts). After 3 failures, stop the monitor task and emit an `error(RuntimeErrorSnapshot(code: "E_TUN_RECOVERY_EXHAUSTED", ...))` event (reusing the existing `RuntimeEvent.error` case — no new event needed). Implement exponential backoff: 2s → 4s → 8s between attempts.
- **`MihomoRuntimeManager.swift:399-446`**: In `stop()`, after `terminateMihomo()` (XPC helper path), poll `healthCheck()` for up to 3 seconds. If the process is still responding, kill it forcibly. Note: the **sudo path** already handles SIGTERM → SIGKILL in `SudoMihomoLauncher.terminate()` (lines 105-121), so this hardening only applies to the XPC helper path. The XPC helper itself should also be updated to support forceful termination; alternatively, fall back to `Process()` with `kill` for the helper-launched PID.
- **`MihomoRuntimeManager.swift:697-722`**: Replace `verifyTUNInterface()` hardcoded `ifconfig utun120` with `ifconfig -l` to list all interface names, filter for `utun*`, then check each with `ifconfig <name>` for `UP` flag and IP in the `198.18.x.x` range (mihomo gVisor default subnet).

#### 3. ModeCoordinator Visibility

- **`ModeCoordinator.swift:229-245`**: When `resolveSystemProxyController()` returns `nil` in `startSystemProxyGuard()`, emit a `RuntimeEvent.guardUnavailable(reason:)` instead of silently swallowing.
- **`ModeCoordinator.swift`**: Add `case guardUnavailable(reason: String)` to `RuntimeEvent`.
- **`AppViewModel.swift`**: Listen for `guardUnavailable` events and display a non-blocking warning banner in the UI suggesting the user switch to TUN mode.

#### 4. Onboarding Mode Guidance

- **`OnboardingView`**: Add a `ModeRecommendationStep` between helper install and config import.
  - Helper installed → show both modes, recommend System Proxy
  - Helper not installed → recommend TUN, show System Proxy as degraded
- **`AppViewModel.swift`**: Read the user's mode choice from `UserDefaults` on startup.

No automatic fallback — users make an informed explicit choice.

#### 5. Remove Demo Code

- **`Sources/RiptideApp/AppRuntime.swift`**: Delete the entire file. `AppMockTunnelRuntime` and `DemoConfigFactory` are development artifacts not referenced by any production path. Replace with a comment-only placeholder if desired.

#### 6. Documentation

- **`README.md`**: Update Runtime Modes table, `xattr` section, Why Riptide section
- **`CLAUDE.md:206-207`**: Fix Known Limitation #1 (guard requires helper), remove #2 (TUN doesn't use NetworkExtension)
- **`AGENTS.md:146`**: Annotate mode descriptions with signing requirements

#### 7. Tests

| Test | File | What it verifies |
|------|------|-----------------|
| `testRecoveryStopsAfterMaxRetries` | `TUNRecoveryTests.swift` | Recovery stops monitor after 3 consecutive failures |
| `testRecoveryBackoffIncreases` | `TUNRecoveryTests.swift` | Cool-down intervals double: 2s → 4s → 8s |
| `testStopForceKillWhenTerminateFails` | `MihomoCoreManagerTests.swift` | Hung mihomo gets `kill -9` after 3s timeout |
| `testGuardUnavailableEventInSystemProxyMode` | `AppShellWorkflowTests.swift` | `guardUnavailable` event emitted when helper absent in System Proxy mode |
| Remove any existing `tunUnavailable` tests | `MihomoCoreManagerTests.swift` | Dead code cleanup |

## Non-Goals

- Sing-box integration (separate initiative)
- HTTP/2 transport implementation (separate initiative)
- MITM certificate generation (separate initiative)
- WebDAV XML decoder (separate initiative)
- PacketTunnelProvider hot-reload (separate initiative)
- Homebrew formula SHA256 population (requires actual release build)
- Apple code signing setup (requires $99/year Developer Program)

## Constraints

- No new external dependencies
- No existing API signature changes (only additive: new event case)
- All 491 existing tests must continue passing
- macOS 14+ only (unchanged)

## Files Changed

| File | Change |
|------|--------|
| `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift` | Remove `tunUnavailable`, harden recovery, dynamic TUN detection, forceful shutdown |
| `Sources/Riptide/AppShell/ModeCoordinator.swift` | `guardUnavailable` event emission |
| `Sources/RiptideApp/AppViewModel.swift` | Listen for `guardUnavailable` events |
| `Sources/RiptideApp/Views/OnboardingView.swift` | Mode recommendation step |
| `Sources/RiptideApp/AppRuntime.swift` | Delete |
| `README.md` | Mode table, TUN description, onboarding guidance |
| `CLAUDE.md` | Known Limitations updates |
| `AGENTS.md` | Mode annotations |
| `Tests/RiptideTests/TUNRecoveryTests.swift` | 2 new tests |
| `Tests/RiptideTests/MihomoCoreManagerTests.swift` | 1 new test, remove dead-code tests |
| `Tests/RiptideTests/AppShellWorkflowTests.swift` | 1 new test |
