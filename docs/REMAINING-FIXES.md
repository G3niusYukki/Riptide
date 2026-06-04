# Remaining Fixes — v2.4.1 audit follow-up

> Handoff document. Five of the eighteen defects surfaced by the v2.4.1
> code audit (2026-06) have been fixed and committed on `master`; twelve
> remain. This file pins down exactly what each remaining fix should do, so a
> future session can pick it up without re-discovering the context.
>
> The completed commits are listed at the bottom for reference.

## Conventions

For every fix below:

1. **TDD**: write a failing test first, confirm it fails for the right reason,
   then apply the production fix, confirm the test passes, run the full
   suite (`swift test` — currently 616 tests) to confirm no regression.
2. **One commit per fix** with the prescribed commit message.
3. **swiftlint --strict** must remain green.
4. **Public API changes** must update all call sites and call `swift build`
   before commit.
5. New tests go in `Tests/RiptideTests/` and follow the Swift Testing
   `@Suite` / `@Test` style (`import Testing`, `#expect`, `@testable import Riptide`).
   XCTest is reserved for `WebDAVClient` (legacy).

---

## FIX-6 — `MihomoConfigGenerator.yamlEscape` mid-string `:`

**Status**: ⏸ Paused — design question.
**Risk**: 🟡 Medium (could break the existing IPv6 test).

**Why it was flagged**:
The character set is
`CharacterSet(charactersIn: "#\"'{}[]\n,&*?|<>!=%@")`.
`:` is intentionally omitted because in YAML *flow-scalar value position*
(`name: value`, `server: value`, `password: value`), a `:` is fine as long as
it is not followed by whitespace and the value is not a `key:` shorthand.
The omission is documented in the doc-comment:
> Note: Colons are NOT escaped as they are common in IPv6 addresses and
> don't cause issues in list item contexts (not key-value contexts)

**The actual concern**:
Mid-string `:` *can* be ambiguous when the string is part of a list of
strings that flow together (`- a: b - c`), or when a string starts with `:`
and the parser confuses it for a mapping. Neither case applies to
`MihomoConfigGenerator` output, where every escaped string is followed by
a newline and is not part of a list-of-mappings key position.

**Decision needed**: confirm we want to keep the current "values are
forgiving" behavior. If yes, **close this fix as WONTFIX** and link to
this comment. If we want stricter YAML, add `:` to the character set and
update `testYAMLEscapingInServer` to expect `"2001:db8::1"` quoted.

**Files**:
- `Sources/Riptide/Mihomo/MihomoConfigGenerator.swift` (L22-32)
- `Tests/RiptideTests/MihomoConfigGeneratorTests.swift` (L590-614 — IPv6 test)

**Commit** (if done): `fix(config-gen): wrap strings containing colons in quotes`

---

## FIX-7 — `MihomoPaths.pathForVersion` cache

**Why it was flagged**:
`pathForVersion` is called on every `MihomoRuntimeManager.start(...)`
and from the recovery watchdog. The current implementation walks the
sidecar directory and matches `mihomo-macos-*` against the requested
version. With a dozen or so sidecar versions and a 50ms stat budget per
path, recovery-loop iteration can spend 200-600ms on path resolution alone.

**Files**:
- `Sources/Riptide/Mihomo/MihomoPaths.swift` (modify)
- New: `Tests/RiptideTests/MihomoPathsTests.swift`

**Changes**:
1. Add `private var cache: [String: URL] = [:]` (and a single `os_unfair_lock`
   around it — `MihomoPaths` is currently a struct, so either make it an
   actor or wrap in `OSAllocatedUnfairLock`).
2. `pathForVersion(_ version: String) -> URL?` — check cache first, fall
   back to disk walk, populate cache on hit.
3. `downloadAndExtract(...)` invalidates the cache entry for the affected
   version (or the entire cache if version-keyed by hash).

**TDD**:
- `pathForVersion_returnsCached_afterFirstCall` — second call returns
  without re-walking (use a temp dir, count `FileManager.default.contentsOfDirectory`
  invocations via a subclass, or just assert identical URL).
- `pathForVersion_returnsNil_forUnknownVersion`.

**Commit**: `perf(mihomo-paths): memoize pathForVersion with version-keyed cache`

---

## FIX-8 — `WebDAVClient.PropfindParserDelegate` percent-decode `currentHref` once

**Why it was flagged**:
`currentHref` accumulates raw text and is appended directly to `files`
without percent-decoding. WebDAV servers (e.g. Nextcloud) return
`/dav/path/%E4%B8%AD%E6%96%87.txt` for non-ASCII filenames. The current code
preserves the percent-encoded form, so `WebDAVFile.name` becomes
`%E4%B8%AD%E6%96%87.txt` and the SwiftUI client shows the encoded form
to users.

The `+=` in `parser(_:foundCharacters:)` (L331-333, L345) is fine for
XML-parser-chunked text. The fix is to call
`currentHref.removingPercentEncoding ?? currentHref` once, on
`didEndElement` for `D:response`.

**Files**:
- `Sources/Riptide/Sync/WebDAVClient.swift` (L360-380, in `PropfindParserDelegate`)
- `Tests/RiptideTests/WebDAVClientTests.swift` (extend XCTest)

**Changes**:
1. Inside `didEndElement` for `response`, add
   `let decodedHref = currentHref.removingPercentEncoding ?? currentHref`
   before computing `path` and `name`.

**TDD**:
- `parsePropfind_decodesPercentEncodedHref` — feed a PROPFIND XML response
  with `/dav/%E4%B8%AD%E6%96%87.txt`, expect `name == "中文.txt"`.

**Commit**: `fix(webdav): percent-decode href once in PROPFIND parser`

---

## FIX-9 — `ConfigSyncManager.syncFromRemote` namespace + delete error propagation

**Why it was flagged**:
1. Remote files in the WebDAV config-sync directory are listed/downloaded
   with no namespace prefix, so a user that drops a `vacation.jpg` into
   the same WebDAV folder gets spurious "config changed" prompts.
2. When deleting a local file that no longer exists remotely, the
   `try?` silently swallows `WebDAVError.notFound`, but real delete
   errors (401, 403, 507) are also swallowed by the same `try?`.

**Files**:
- `Sources/Riptide/Config/WebDAVSync.swift` (the `ConfigSyncManager`
  class/actor)
- `Tests/RiptideTests/ConfigSyncManagerTests.swift` (extend or new)

**Changes**:
1. Define `private static let configFilePrefix = "riptide-config-"`
   and `configFileExtension = ".yaml"`. Filter `listFiles` results to
   names with the prefix and extension.
2. Strip the prefix and extension when materialising local filenames.
3. In `syncFromRemote`, when a remote file is gone:
   - Local delete: keep `try?` (file already gone, that's fine).
   - Remote delete (when *pushing* deletions): replace `try?` with `try`
     and surface the error via `Result<Void, Error>` so the caller can
     log it.

**TDD**:
- `listFiles_filtersOut_nonConfigFiles` — feed `[a.yaml, b.jpg, riptide-config-c.yaml]`,
  expect only the third.
- `syncFromRemote_propagatesDeleteError_whenRemoteFails` — mock the
  WebDAV actor to throw on DELETE, expect the sync result to surface the error.

**Commit**: `fix(config-sync): namespace config files and surface delete errors`

---

## FIX-10 — `LogbookStore.flush()` atomic handle/date-string clearing

**Why it was flagged**:
`LogbookStore.flush()` does roughly:
```swift
let handle = fileHandle
fileHandle = nil
let dateString = currentDateString
currentDateString = ""
```
on `actor LogbookStore` — but each individual assignment is its own
actor-isolated step, so a concurrent `append(_:)` in between can observe
`fileHandle == nil` and `currentDateString == "<stale date>"`, then
re-create the handle against the old date string.

**Files**:
- `Sources/Riptide/Logbook/LogbookStore.swift` (modify)
- `Tests/RiptideTests/LogbookStoreTests.swift` (extend)

**Changes**:
Replace the three separate assignments with a single
`private struct LogbookHandles { var handle: FileHandle?; var dateString: String }`
property `private var handles: LogbookHandles`. The "close and reset" path
mutates `handles` once; the "open new handle" path also mutates it once.

**TDD**:
- `flush_midflightAppend_doesNotOpenStaleHandle` — race a `flush()` with
  100 concurrent `append(_:)` calls; assert the new file handle's date
  string matches the date at *close*, not the date at *open*.

**Commit**: `fix(logbook): make flush and ensureHandle atomic on shared struct`

---

## FIX-11 — `ClosedConnectionWatcher.tick()` batch records

**Why it was flagged**:
The current tick:
```swift
for record in closedRecords {
    await writer.recordConnectionClosed(record)  // N actor hops
}
```
calls into the `LogbookStore` actor once per record. With a 5-second
tick and a 1k conn/s churn, that's 5000 actor hops per tick. mihomo
delivers `connections` in a single REST call, so records can be batched
at the watcher boundary instead of at the writer boundary.

**Files**:
- `Sources/Riptide/Logbook/ClosedConnectionWatcher.swift` (modify)
- `Sources/Riptide/Logbook/LogbookStore.swift` (add `recordBatch(_:)` method)
- `Tests/RiptideTests/LogbookStoreTests.swift` (extend)

**Changes**:
1. Add `func recordBatch(_ records: [ConnectionCloseRecord])` on
   `LogbookStore` that calls `append(_:)` in a tight loop inside the
   actor (still serialised, but no message-passing per record).
2. Replace the per-record loop in `ClosedConnectionWatcher.tick()` with
   a single `await writer.recordBatch(records)`.

**TDD**:
- `recordBatch_writesAllRecords` — pass 1000 records, assert all are in
  the log file.
- `tick_batchesRecords_toWriter` — verify the watcher calls
  `recordBatch` with the full list (use a mock writer).

**Commit**: `perf(logbook): batch connection-close records in watcher tick`

---

## FIX-12 — `AppViewModel` extract `@MainActor AppState`

**Why it was flagged**:
`AppViewModel` is a SwiftUI `ObservableObject` that mixes:
- Long-lived, MainActor-isolated UI state (`@Published var` properties).
- Calls into `ModeCoordinator` (an actor) that may be invoked from any
  context.
- Configuration load that touches disk.

The current implementation guards `@Published` mutations with
`Task { @MainActor in ... }` blocks scattered across the class. A
dedicated `@MainActor final class AppState` would let Swift's compiler
enforce the isolation and make the data flow obvious.

**This is the largest behavioral change** of the remaining 12 — it touches
the UI surface and may require adjustments in `RiptideAppUITests`.

**Files**:
- `Sources/RiptideApp/AppViewModel.swift` (rewrite — extract `AppState`)
- `Tests/RiptideAppUITests/` (verify nothing breaks; minor adjustments
  likely).

**Changes**:
1. New `final class AppState: ObservableObject` annotated `@MainActor`.
2. Move all `@Published` properties into `AppState`.
3. `AppViewModel` becomes a thin wrapper that holds an `AppState`
   reference plus injected services (`ModeCoordinator`, `ProfileStore`).
4. UI bindings go through `viewModel.state.foo` or via
   `@EnvironmentObject var state: AppState`.

**TDD**:
- Existing `AppShellWorkflowTests` should still pass.
- Add `AppState_mutations_areMainActorIsolated` — calling a mutating
  method from a non-main context should be a compile error
  (test via `swift build` with a sample compile-fail snippet, or via
  the runtime: assert `Thread.isMainThread` inside the mutation).

**Commit**: `fix(app-shell): isolate AppViewModel mutable state on @MainActor`

---

## FIX-13 — `MihomoRuntimeManager.attemptTUNRecovery` userRequestedStop flag

**Why it was flagged**:
When the user clicks "Stop" in the UI, `stop()` is called, then the TUN
health probe (in `attemptTUNRecovery`) wakes up, sees `isRunning == false`,
and immediately calls `try await start(...)` — re-launching mihomo the
user just stopped. This is racy: the user's intent is overridden by
the recovery loop.

**Files**:
- `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift` (modify)
- `Tests/RiptideTests/MihomoRuntimeManagerTests.swift` (extend)

**Changes**:
1. Add `private var userRequestedStop: Bool = false` to the actor.
2. In `stop()`: set `userRequestedStop = true` before tearing down.
3. In `start(...)`: clear `userRequestedStop = false` once `isRunning`
   becomes true.
4. In `attemptTUNRecovery`: if `userRequestedStop`, return early *before*
   calling `start(...)`.

**TDD**:
- `attemptTUNRecovery_doesNothing_afterUserStop` — set
  `userRequestedStop = true`, call `attemptTUNRecovery()`, assert
  `start(...)` was not called.
- `attemptTUNRecovery_resumes_afterStart` — clear flag, call
  `attemptTUNRecovery()`, assert `start(...)` was called.

**Commit**: `fix(mihomo-runtime): do not auto-recover TUN after user-initiated stop`

---

## FIX-14 — `FakeIPPool` concurrency safety

**Why it was flagged**:
`FakeIPPool` is currently `final class FakeIPPool: @unchecked Sendable`
with a `[IPAddress: Domain]` dictionary mutated from multiple call sites.
The `@unchecked` is a lie: the class has no internal lock and the
dictionary can race. Symptoms: intermittent DNS hijack failures
under load, or duplicate IPs returned to different concurrent DNS
queries (rare but possible).

**Files**:
- `Sources/Riptide/DNS/FakeIPPool.swift` (modify)
- `Tests/RiptideTests/FakeIPPoolTests.swift` (extend or new)

**Changes**:
Two options:
1. **Convert to `actor`** (cleanest; changes public API from sync to async).
2. **Wrap in `OSAllocatedUnfairLock`** (keeps sync API; explicit lock).

Option 2 is preferred for callers that use the pool inside synchronous
code paths. Implementation:
```swift
public final class FakeIPPool: Sendable {
    private let state = OSAllocatedUnfairLock<State>(initialState: .init())
    // ...all public methods become `state.withLock { ... }`...
}
```

**TDD**:
- `allocate_concurrent_returnsDistinctIPs` — fire 1000 concurrent
  `allocate(for: domain)` tasks against the same domain, assert all
  return the same IP (idempotent). Then against 1000 different domains,
  assert all IPs are distinct.

**Commit**: `fix(dns): make FakeIPPool concurrency-safe with OSAllocatedUnfairLock`

---

## FIX-15 — `SudoMihomoLauncher.terminate()` UAF prevention

**Why it was flagged**:
`terminate()` does roughly:
```swift
proc.terminate()
try? await Task.sleep(...)
// ← `proc` may have been deallocated here, OR
//    another launch may have replaced it
if proc.isRunning { proc.terminate() }
```
Without a lock, the `proc` captured at the top of `terminate()` can be
replaced by a concurrent `launch()` between the `Task.sleep` and the
second `terminate` call, leading to use-after-free or, worse,
terminating a freshly launched mihomo that the user just started.

**Files**:
- `Sources/Riptide/Mihomo/SudoMihomoLauncher.swift` (modify)
- `Tests/RiptideTests/SudoMihomoLauncherTests.swift` (new or extend)

**Changes**:
1. Wrap the stored process in
   `private let procStorage = OSAllocatedUnfairLock<Process?>(initialState: nil)`.
2. `terminate()` captures the current process under the lock, releases
   the lock, then performs the sleep + check + terminate outside the
   lock. Re-acquire the lock to compare-and-replace.

**TDD**:
- `terminate_doesNotKillFreshProcess_afterConcurrentLaunch` — start a
  "process" A, call `terminate()` (which sleeps), launch "process" B
  during the sleep, ensure B survives.
- `terminate_killsOriginalProcess_whenNoRelaunch` — start A, call
  `terminate()`, assert A is terminated.

**Commit**: `fix(sudo-launcher): prevent use-after-free in terminate() under reentrancy`

---

## FIX-16 — `HelperToolConnection.isHelperInstalled()` lock

**Why it was flagged**:
`HelperToolConnection.isHelperInstalled()` uses
`var hasResponded = false` mutated from both the XPC reply handler and
the timeout path. The XPC reply handler runs on an arbitrary dispatch
queue, so the read in the timeout path is racy. Rare, but can manifest
as the helper tool being reported as "not installed" immediately after
the user just installed it (timeout wins the race).

**Files**:
- `Sources/Riptide/XPC/HelperToolConnection.swift` (modify)
- `Tests/RiptideTests/HelperToolConnectionTests.swift` (extend)

**Changes**:
1. Replace `var hasResponded = false` with
   `private let responseState = OSAllocatedUnfairLock<ResponseState>`.
2. All reads and writes go through `responseState.withLock { ... }`.

**TDD**:
- `isHelperInstalled_returnsTrue_whenReplyArrivesBeforeTimeout` —
  invoke the call, deliver a reply, assert `true`.
- `isHelperInstalled_returnsFalse_onTimeout` — invoke, never reply,
  fast-forward the timeout, assert `false`.
- Stress: 1000 interleaved reply/timeout scenarios, assert no
  inconsistency.

**Commit**: `fix(xpc): guard isHelperInstalled response with OSAllocatedUnfairLock`

---

## FIX-17 — `MihomoDownloader.listLocalVersions` skip symlinks

**Why it was flagged**:
`listLocalVersions` enumerates the mihomo sidecar directory and returns
`mihomo-macos-<arch>-<version>` basenames. If the user (or a future
install script) creates a symlink in that directory, it shows up as a
"local version" and `MihomoRuntimeManager.start(...)` will try to
launch it — typically failing because symlink resolution finds nothing.

**Files**:
- `Sources/Riptide/Mihomo/MihomoDownloader.swift` (modify)
- `Tests/RiptideTests/MihomoDownloaderTests.swift` (extend)

**Changes**:
In the directory walk, check
`(try? resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true`
and skip such entries.

**TDD**:
- `listLocalVersions_skipsSymlinks` — create a real binary and a
  symlink in a temp dir, assert only the real binary appears in the
  returned list.

**Commit**: `fix(mihomo): skip symlinks in listLocalVersions`

---

## FIX-18 — `MihomoConfigGenerator.generate` reject duplicate proxy names

**Why it was flagged**:
mihomo rejects configs with duplicate `name:` fields under `proxies:`
and `proxy-groups:`. The current generator happily emits duplicates
if the user provides them. mihomo then refuses to load, and the
failure surfaces as a generic "config invalid" error from the sidecar.

**Files**:
- `Sources/Riptide/Mihomo/MihomoConfigGenerator.swift` (modify)
- `Tests/RiptideTests/MihomoConfigGeneratorTests.swift` (extend)

**Changes**:
1. Add `case duplicateProxyName(String)` to `GenerationError`.
2. After computing `let names = config.proxies.map(\.name)`, check
   `Set(names).count == names.count`. If not, throw
   `GenerationError.duplicateProxyName(...)` with the first duplicate.
3. Same check for `config.proxyGroups.map(\.id)`.

**TDD**:
- `generate_throws_duplicateProxyName` — feed two proxies with the
  same name, expect `.duplicateProxyName`.
- `generate_throws_duplicateProxyGroupName` — same for groups.
- `generate_succeeds_withDistinctNames` — regression.

**Commit**: `fix(config-gen): reject configs with duplicate proxy names`

---

## Completed fixes (v2.4.1 audit, committed)

| # | Commit | Files |
|---|--------|-------|
| FIX-A | `fix(mihomo): verify SHA-256 of downloaded binaries against GitHub asset digest` | `MihomoDownloader.swift`, `MihomoDownloaderTests.swift` |
| FIX-1 | `fix(load-balancer): use stable per-instance seed and deterministic nil-host fallback` | `LoadBalancer.swift`, `LoadBalancerTests.swift` |
| FIX-2 | `fix(mihomo-config): throw on unsupported proxy kinds (.reality/.anytls/.ssh)` | `MihomoConfigGenerator.swift`, `MihomoConfigGeneratorTests.swift`, `MihomoRuntimeManager.swift` |
| FIX-3 | `fix(app-shell): derive stable provider IDs via FNV-1a instead of String.hashValue` | new `StableHash.swift` + `StableHashTests.swift`, `LoadBalancer.swift`, `ModeCoordinator.swift` |
| FIX-4 | `refactor(mihomo-runtime): extract requireAPI helper, remove duplicated boilerplate` | `MihomoRuntimeManager.swift` |
| FIX-5 | `refactor(webdav): extract WebDAVShared path resolver and PROPFIND body constant` | new `BaseWebDAVClient.swift` + `WebDAVSharedTests.swift`, `WebDAVClient.swift`, `Config/WebDAVSync.swift` |

Test count: **593 → 616** (+23 tests across the 5 fixes).

## Future session bootstrap

When picking up the remaining 12 fixes:

```bash
# Confirm the current state.
swift test --filter "MihomoConfigGeneratorTests|MihomoDownloaderTests|LoadBalancerTests|StableHashTests|WebDAVSharedTests"
git log --oneline -10

# For each fix in this doc, in order:
#   1. write the failing test
#   2. swift test --filter <new-test>      # confirm failure
#   3. apply the production change
#   4. swift test --filter <new-test>      # confirm pass
#   5. swift test                           # full suite regression check
#   6. swiftlint --strict
#   7. git add <files> && git commit -m "<commit message from doc>"
```
