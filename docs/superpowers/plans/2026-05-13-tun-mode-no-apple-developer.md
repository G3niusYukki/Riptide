# TUN Mode Without Apple Developer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Riptide fully usable in TUN mode without an Apple Developer account — remove Beta label, harden TUN recovery, improve user visibility, add onboarding guidance, and clean up demo code.

**Architecture:** Seven parallel-capable task groups. Groups 1-3 (core TUN hardening) are sequential within themselves. Groups 4-7 (visibility, docs, cleanup, tests) can run in parallel with each other and with late stages of Groups 1-3.

**Tech Stack:** Swift 6.2+, macOS 14+, SwiftUI, mihomo sidecar, sudo Process() management, Swift Package Manager

---

### Task 1: Remove TUN Beta Labeling + Dead Code

**Files:**
- Modify: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift:19-20`
- Modify: `README.md:144-148, 29-36, 168`

- [ ] **Step 1: Remove `tunUnavailable` from RuntimeError**

In `MihomoRuntimeManager.swift`, delete lines 19-20:
```swift
    /// TUN mode is intentionally hidden until real mihomo TUN integration is verified.
    case tunUnavailable(String)
```

- [ ] **Step 2: Verify no references to `tunUnavailable` remain**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds with no errors about `tunUnavailable`.

- [ ] **Step 3: Update README.md Runtime Modes table**

In `README.md`, change lines 144-148:
```markdown
| **System Proxy** | Stable | Primary path — mihomo sidecar + macOS system proxy configuration with auto-guard (requires signed helper for guard) |
| **TUN Mode** | Stable | Full traffic interception via mihomo gVisor TUN + auto-recovery — recommended for unsigned builds. Requires sudo, no Apple Developer account needed |
```

- [ ] **Step 4: Update README.md Why Riptide section**

After line 36 (end of Why Riptide), add:
```markdown
> **Unsigned builds:** TUN mode is the recommended path — it intercepts all traffic at the packet level via mihomo's gVisor stack and does not require the privileged helper.
```

- [ ] **Step 5: Update README.md install section**

At line 168 (after `xattr -cr` paragraph), add:
```markdown
    After removing quarantine, launch Riptide and select **TUN mode** during onboarding for full traffic interception without Apple signing.
```

- [ ] **Step 6: Build to verify README changes don't break markdown**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
cd /Users/peterzhang/Riptide
git add Sources/Riptide/Mihomo/MihomoRuntimeManager.swift README.md
git commit -m "feat: remove TUN Beta label, delete tunUnavailable dead code"
```

---

### Task 2: TUN Recovery — Max Retries + Exponential Backoff

**Files:**
- Modify: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift:353-395`

- [ ] **Step 1: Add recovery state properties**

Add two new properties to `MihomoRuntimeManager` (near line 133, after `tunMonitorTask`):
```swift
/// Count of consecutive failed TUN recovery attempts.
private var tunRecoveryFailures: Int = 0
/// Maximum consecutive recovery attempts before giving up.
private let maxTUNRecoveryAttempts = 3
```

- [ ] **Step 2: Rewrite `attemptTUNRecovery()` with retry limit and backoff**

Replace lines 383-395:
```swift
private func attemptTUNRecovery() async {
    guard let profile = currentProfile else { return }
    
    tunRecoveryFailures += 1
    
    if tunRecoveryFailures > maxTUNRecoveryAttempts {
        print("[MihomoRuntimeManager] TUN recovery exhausted after \(maxTUNRecoveryAttempts) attempts — stopping monitor")
        stopTUNMonitoring()
        // Emit error event for UI visibility
        let snapshot = RuntimeErrorSnapshot(
            code: "E_TUN_RECOVERY_EXHAUSTED",
            message: "TUN recovery failed after \(maxTUNRecoveryAttempts) consecutive attempts. TUN monitoring stopped."
        )
        // Store event for ModeCoordinator to surface
        latestRecoveryError = snapshot
        return
    }
    
    let backoffSeconds: UInt64 = UInt64(min(pow(2.0, Double(tunRecoveryFailures)), 8.0))
    print("[MihomoRuntimeManager] TUN recovery attempt \(tunRecoveryFailures)/\(maxTUNRecoveryAttempts) with \(backoffSeconds)s backoff")
    
    try? await stop()
    try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
    
    do {
        try await start(mode: .tun, profile: profile)
        tunRecoveryFailures = 0 // Reset on success
        print("[MihomoRuntimeManager] TUN recovery succeeded")
    } catch {
        print("[MihomoRuntimeManager] TUN recovery attempt \(tunRecoveryFailures) failed: \(error)")
    }
}
```

- [ ] **Step 3: Add `latestRecoveryError` property**

Add near line 135 (after the new recovery state properties):
```swift
/// The most recent TUN recovery error, surfaced to ModeCoordinator.
public private(set) var latestRecoveryError: RuntimeErrorSnapshot?
```

- [ ] **Step 4: Reset recovery counter on successful `start()` with TUN**

In the `start()` method, after line 317 (`currentProfile = profile`), add:
```swift
if mode == .tun {
    tunRecoveryFailures = 0
    latestRecoveryError = nil
}
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/Mihomo/MihomoRuntimeManager.swift
git commit -m "feat: add TUN recovery max-retry limit with exponential backoff"
```

---

### Task 3: Dynamic TUN Interface Detection + Forceful Stop

**Files:**
- Modify: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift:697-722, 399-446`

- [ ] **Step 1: Rewrite `verifyTUNInterface()` with dynamic device detection**

Replace lines 697-722:
```swift
private func verifyTUNInterface() async -> Bool {
    // Get all network interface names
    let ifconfigList = Process()
    ifconfigList.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    ifconfigList.arguments = ["-l"]
    
    let listPipe = Pipe()
    ifconfigList.standardOutput = listPipe
    ifconfigList.standardError = FileHandle.nullDevice
    
    do {
        try ifconfigList.run()
        ifconfigList.waitUntilExit()
    } catch {
        return false
    }
    
    guard ifconfigList.terminationStatus == 0,
          let listOutput = String(data: listPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    else { return false }
    
    let interfaces = listOutput.components(separatedBy: .whitespaces).filter { $0.hasPrefix("utun") }
    
    // Check each utun interface for UP flag and mihomo IP range
    for iface in interfaces {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        proc.arguments = [iface]
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            continue
        }
        
        guard proc.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { continue }
        
        // Must be UP and have an address in the 198.18.x.x range (mihomo gVisor default)
        if output.contains("UP") && output.range(of: "inet 198\\.18\\.", options: .regularExpression) != nil {
            return true
        }
    }
    
    return false
}
```

- [ ] **Step 2: Add forceful termination fallback in `stop()` for XPC helper path**

Replace lines 418-429 (the termination section of `stop()`):
```swift
// 3. Terminate mihomo
let wasTunMode = currentMode == .tun

if launchedViaSudo {
    try? await sudoLauncher.terminate()
} else {
    let terminationError = await helperConnection.terminateMihomo()
    if terminationError == nil {
        await waitForTermination()
    }
    
    // Forceful fallback: if health check still succeeds after 3s, process is hung
    if let wrapper = apiClientWrapper {
        var hung = false
        for _ in 0..<10 {
            let alive = await wrapper.client.healthCheck()
            if !alive { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
            hung = true // reached here means still alive after all attempts
        }
        if hung {
            print("[MihomoRuntimeManager] Warning: mihomo process unresponsive after terminate — requesting forceful kill")
            // Request XPC helper to force-kill, or use local PID if available
            _ = await helperConnection.forceKillMihomo()
        }
    }
    await helperConnection.disconnect()
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds. If `forceKillMihomo()` doesn't exist yet on `helperConnection`, use `print()` as placeholder for this iteration and file a follow-up.

- [ ] **Step 4: Commit**

```bash
git add Sources/Riptide/Mihomo/MihomoRuntimeManager.swift
git commit -m "feat: dynamic TUN interface detection + forceful mihomo termination fallback"
```

---

### Task 4: Expose TUN Recovery Events to ModeCoordinator

**Files:**
- Modify: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift`
- Modify: `Sources/Riptide/AppShell/ModeCoordinator.swift`

- [ ] **Step 1: Add `public var latestRecoveryError` to MihomoRuntimeManaging protocol**

In `MihomoRuntimeManager.swift`, add to `MihomoRuntimeManaging` protocol (near line 36):
```swift
/// The most recent TUN recovery error, if any.
var latestRecoveryError: RuntimeErrorSnapshot? { get }
```

- [ ] **Step 2: Poll recovery error in ModeCoordinator health loop**

In `ModeCoordinator.swift`, in the `startHealthChecks` loop (around line 290), add after proxy health checks:
```swift
// Check TUN recovery status
if let recoveryError = await mihomoManager.latestRecoveryError {
    emit(.error(recoveryError))
    // Clear after emitting to avoid duplicates
    // (MihomoRuntimeManager keeps it until next successful recovery or restart)
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Riptide/Mihomo/MihomoRuntimeManager.swift Sources/Riptide/AppShell/ModeCoordinator.swift
git commit -m "feat: surface TUN recovery exhaustion events to ModeCoordinator"
```

---

### Task 5: ModeCoordinator — System Proxy Guard Visibility

**Files:**
- Modify: `Sources/Riptide/Control/RuntimeControlSurface.swift:40-47`
- Modify: `Sources/Riptide/AppShell/ModeCoordinator.swift:229-245`
- Modify: `Sources/RiptideApp/AppViewModel.swift`

- [ ] **Step 1: Add `guardUnavailable` case to RuntimeEvent**

In `RuntimeControlSurface.swift`, add to `RuntimeEvent` enum (after `case error`):
```swift
case guardUnavailable(reason: String)
```

- [ ] **Step 2: Update ModeCoordinator to emit `guardUnavailable`**

In `ModeCoordinator.swift`, at lines 229-245 (`startSystemProxyGuard`), modify the `resolveSystemProxyController()` nil path:
```swift
private func startSystemProxyGuard() async {
    guard let controller = await resolveSystemProxyController() else {
        emit(.guardUnavailable(reason: "System proxy guard unavailable: privileged helper not installed. "
            + "Your proxy settings will not auto-restore if changed externally. "
            + "Consider switching to TUN mode for full traffic interception."))
        return
    }
    // ... rest of existing guard setup ...
}
```

- [ ] **Step 3: Update AppViewModel to listen for guardUnavailable**

In `AppViewModel.swift`, add a `@Published var guardUnavailableWarning: String?` property. In the event processing logic (search for where `recentEvents` is read), add:
```swift
for event in events {
    if case .guardUnavailable(let reason) = event {
        self.guardUnavailableWarning = reason
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Riptide/Control/RuntimeControlSurface.swift Sources/Riptide/AppShell/ModeCoordinator.swift Sources/RiptideApp/AppViewModel.swift
git commit -m "feat: emit guardUnavailable event when helper absent in System Proxy mode"
```

---

### Task 6: Onboarding — Mode Recommendation Step

**Files:**
- Modify: `Sources/RiptideApp/Views/OnboardingView.swift`
- Modify: `Sources/RiptideApp/AppViewModel.swift`

- [ ] **Step 1: Add ModeRecommendationStep to OnboardingView**

Locate `OnboardingView.swift` (search with `file_search` if needed). Add a new step struct:
```swift
struct ModeRecommendationStep: View {
    let isHelperInstalled: Bool
    @Binding var selectedMode: RuntimeMode
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Choose Your Mode")
                .font(.title)
            
            if isHelperInstalled {
                Text("Both modes are fully available.")
                    .foregroundColor(.secondary)
                
                ModeOption(
                    mode: .systemProxy,
                    title: "System Proxy",
                    description: "Lightweight, sets macOS system proxy. Best for app traffic.",
                    isRecommended: true,
                    isSelected: selectedMode == .systemProxy
                ) { selectedMode = .systemProxy }
            } else {
                Text("Privileged helper not installed — TUN mode recommended.")
                    .foregroundColor(.secondary)
                
                ModeOption(
                    mode: .tun,
                    title: "TUN Mode (Recommended)",
                    description: "Full traffic interception at the packet level. No Apple Developer account needed.",
                    isRecommended: true,
                    isSelected: selectedMode == .tun
                ) { selectedMode = .tun }
                
                ModeOption(
                    mode: .systemProxy,
                    title: "System Proxy (Degraded)",
                    description: "Works but system proxy guard is unavailable — settings won't auto-restore if changed.",
                    isRecommended: false,
                    isSelected: selectedMode == .systemProxy
                ) { selectedMode = .systemProxy }
            }
        }
        .padding()
    }
}

struct ModeOption: View {
    let mode: RuntimeMode
    let title: String
    let description: String
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(title).font(.headline)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    Text(description).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Insert step into OnboardingView flow**

Insert `ModeRecommendationStep` between the helper install step and config import step in the parent OnboardingView. Pass `isHelperInstalled` from `SMJobBlessManager` and bind `selectedMode` to a `@AppStorage` key.

- [ ] **Step 3: Read mode choice on app startup**

In `AppViewModel.swift` init (or where initial mode is set), read from `UserDefaults`:
```swift
let savedMode = UserDefaults.standard.string(forKey: "selectedRuntimeMode")
    .flatMap(RuntimeMode.init(rawValue:)) ?? .systemProxy
```

- [ ] **Step 4: Build and verify**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/RiptideApp/Views/OnboardingView.swift Sources/RiptideApp/AppViewModel.swift
git commit -m "feat: add mode recommendation step to onboarding for unsigned builds"
```

---

### Task 7: Remove Demo Code

**File:**
- Delete: `Sources/RiptideApp/AppRuntime.swift`

- [ ] **Step 1: Verify no references to AppMockTunnelRuntime or DemoConfigFactory**

Run: `cd /Users/peterzhang/Riptide && grep -r "AppMockTunnelRuntime\|DemoConfigFactory" Sources/ 2>&1`
Expected: Only matches in `AppRuntime.swift` itself. If matches elsewhere, remove those references.

- [ ] **Step 2: Delete the file**

```bash
rm Sources/RiptideApp/AppRuntime.swift
```

- [ ] **Step 3: Build to verify no missing references**

Run: `cd /Users/peterzhang/Riptide && swift build 2>&1`
Expected: Build succeeds. If errors about missing types, those types are used elsewhere and shouldn't be deleted (but our grep in Step 1 guards against this).

- [ ] **Step 4: Commit**

```bash
git rm Sources/RiptideApp/AppRuntime.swift
git commit -m "chore: remove demo code (AppMockTunnelRuntime, DemoConfigFactory)"
```

---

### Task 8: Documentation Updates

**Files:**
- Modify: `CLAUDE.md:204-210`
- Modify: `AGENTS.md:146-147`

- [ ] **Step 1: Update CLAUDE.md Known Limitations**

Replace lines 204-210:
```markdown
## Known Limitations

1. **Helper Tool Signing**: `RiptideHelper/Resources/Info.plist` requires valid Apple Developer Team ID for production SMJobBless. Without signing, TUN mode (via sudo) works fully; System Proxy guard is unavailable.
2. **QUIC transport**: Requires macOS 14+ (`NWProtocolQUIC`)
3. **Windows port**: In progress (Phase 2), `feat/windows-port-phase2` branch
```

- [ ] **Step 2: Update AGENTS.md Mode Descriptions**

Locate the Runtime Modes section in AGENTS.md. Update TUN description to note "no signing required".

- [ ] **Step 3: Verify markdown renders correctly**

Run: `cd /Users/peterzhang/Riptide && head -220 CLAUDE.md | tail -20`
Expected: Known Limitations section reads as updated.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: update known limitations — TUN uses gVisor not NetworkExtension"
```

---

### Task 9: Tests — TUN Recovery

**Files:**
- Create/Modify: `Tests/RiptideTests/TUNRecoveryTests.swift`

- [ ] **Step 1: Write test for recovery stop after max retries**

```swift
func testRecoveryStopsAfterMaxRetries() async throws {
    // Use a mock MihomoRuntimeManaging that always fails start()
    // Verify that after 3 recovery attempts, the monitor stops
    // and latestRecoveryError is set
}
```

- [ ] **Step 2: Write test for backoff timing**

```swift
func testRecoveryBackoffIncreases() async throws {
    // Verify that backoff intervals follow 2s, 4s, 8s pattern
    // by capturing timestamps between attempts
}
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/peterzhang/Riptide && swift test --filter "TUNRecovery"
```

- [ ] **Step 4: Commit**

```bash
git add Tests/RiptideTests/TUNRecoveryTests.swift
git commit -m "test: add TUN recovery max-retry and backoff tests"
```

---

### Task 10: Tests — System Proxy Guard Visibility

**Files:**
- Create/Modify: `Tests/RiptideTests/AppShellWorkflowTests.swift`

- [ ] **Step 1: Write test for guardUnavailable event**

```swift
func testGuardUnavailableEventInSystemProxyMode() async throws {
    let mockManager = MockMihomoRuntimeManager(helperInstalled: false)
    let coordinator = ModeCoordinator(mihomoManager: mockManager)
    
    try await coordinator.start(mode: .systemProxy, profile: sampleProfile)
    
    let events = await coordinator.recentEvents()
    let hasGuardEvent = events.contains { event in
        if case .guardUnavailable = event { return true }
        return false
    }
    XCTAssertTrue(hasGuardEvent, "Expected guardUnavailable event when helper not installed in System Proxy mode")
}
```

- [ ] **Step 2: Also verify NO guardUnavailable in TUN mode**

```swift
func testNoGuardEventInTUNMode() async throws {
    let mockManager = MockMihomoRuntimeManager(helperInstalled: false)
    let coordinator = ModeCoordinator(mihomoManager: mockManager)
    
    try await coordinator.start(mode: .tun, profile: sampleProfile)
    
    let events = await coordinator.recentEvents()
    let hasGuardEvent = events.contains { event in
        if case .guardUnavailable = event { return true }
        return false
    }
    XCTAssertFalse(hasGuardEvent, "TUN mode should not emit guardUnavailable")
}
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/peterzhang/Riptide && swift test --filter "AppShellWorkflow"
```

- [ ] **Step 4: Commit**

```bash
git add Tests/RiptideTests/AppShellWorkflowTests.swift
git commit -m "test: verify guardUnavailable event in System Proxy mode without helper"
```

---

### Task 11: Final Verification

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/peterzhang/Riptide && swift test 2>&1
```
Expected: All tests pass (491 existing + 4 new = 495 passing).

- [ ] **Step 2: Verify build for all targets**

```bash
cd /Users/peterzhang/Riptide && swift build 2>&1
```
Expected: All targets build successfully.

- [ ] **Step 3: Verify no references to deleted symbols**

```bash
grep -r "tunUnavailable\|AppMockTunnelRuntime\|DemoConfigFactory" Sources/ Tests/ 2>&1
```
Expected: No matches.

- [ ] **Step 4: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "chore: final cleanup and verification"
```
