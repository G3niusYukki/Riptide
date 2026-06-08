# ADR-0011: Windows test pyramid target

> **Status:** Accepted · **Date:** 2026-06-08 · **Deciders:** maintainers

## Context

macOS Riptide has a mature test suite: 593 Swift unit tests + 38 XCUITest
UI tests (631 total). Windows currently has ~70 TypeScript unit tests
(vitest) + ~25 Rust unit tests (`cargo test --lib`), for ~95 total. The
catchup plan
([`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §9 Phase D
go criteria) targets **430 tests** by Phase D end.

The gap is 335 tests. Without a structured target, three failure modes
are likely:

1. **Rust-side under-testing.** The Rust core (`src-tauri/src/core/`)
   handles config parsing, URI serialization, logbook, engine routing,
   scripting, scenes, override merging, mode coordination, and
   subscription scheduling — the highest-risk code. If tests are
   written only in TypeScript (the easier surface), the Rust core
   stays under-tested.
2. **E2E over-investment.** Playwright tests are slow (~5 min for a
   full run), flaky on Windows (WebView2 timing), and expensive to
   maintain. If E2E tests are written for logic that should be a
   unit test, the suite becomes slow and brittle.
3. **Coverage blind spots.** Without a per-layer target, it is
   possible to hit 430 tests while leaving entire modules (e.g.
   `core/singbox/`, `core/scripting/`) with zero coverage.

## Decision

**A three-tier test pyramid with explicit per-layer targets and a
coverage gate.**

### Layer 1 (base): Rust unit tests — target 300 tests

Runner: `cargo test --lib` (runs in CI on every PR, ~15 seconds).

Module targets (approximate):

| Module | Target tests | Covers |
|---|---|---|
| `core/config/` (parsing, validation, merging) | 40 | Clash YAML parsing, config schema validation, override merge logic, default injection |
| `core/uri/` (parsing, serialization) | 30 | `ss://`, `vmess://`, `vless://`, `trojan://`, `hysteria2://`, `tuic://` URI round-trip, malformed input |
| `core/logbook/` (paths, store, writer) | 25 | Log rotation, store CRUD, writer flush/shutdown |
| `core/engines/` (router, policy) | 20 | `EngineRouter` policy table, `ProxyKind` dispatch, unknown-kind fallback |
| `core/singbox/` (config generator, downloader) | 20 | Each `ProxyKind` → JSON outbound, SHA-256 pass/fail/empty, version pin |
| `core/mihomo/` (config generator, API client) | 20 | Clash YAML generation, API client request/response, timeout handling |
| `core/scripting/` (Lua/Squirrel sandbox) | 15 | Script load, sandboxed execution, timeout, error propagation |
| `core/scenes/` (CRUD, activation) | 15 | Scene create/read/update/delete, activation ordering, default scene |
| `core/override/` (merging) | 15 | Override apply, conflict resolution, undo, field-level merge |
| `core/mode/` (coordinator) | 15 | Mode toggle (system/proxy/direct/rule), state persistence, transition guards |
| `core/subscription/` (scheduler, parser) | 15 | Subscription fetch, parse, diff, schedule (cron-style), error handling |
| `core/tun/` (service client) | 15 | Pipe IPC command round-trip, timeout, reconnection, malformed response |
| `core/dns/` (resolver, config) | 10 | DNS config generation, resolver selection, fallback chain |
| Other (`core/utils/`, `core/path/`, etc.) | 25 | Utility functions, path resolution, platform detection |

The module targets are **approximate** — the exact distribution will
shift as implementation proceeds. The invariant is the total: 300 Rust
tests.

### Layer 2 (middle): TypeScript unit tests — target 100 tests

Runner: `vitest` (runs in CI on every PR, ~10 seconds).

Module targets (approximate):

| Module | Target tests | Covers |
|---|---|---|
| `src/stores/` (Zustand stores) | 25 | Config store, proxy store, settings store, subscription store — state transitions, selectors, persistence |
| `src/hooks/` (React hooks) | 15 | `useConfig`, `useProxy`, `useMode`, `useSettings` — render counts, dependency tracking, error handling |
| `src/lib/` (IPC wrappers) | 15 | Tauri `invoke` wrappers — argument serialization, error mapping, retry logic |
| `src/components/` (rendering) | 20 | Component snapshot tests, prop validation, conditional rendering, loading/error states |
| `src/i18n/` (internationalization) | 10 | Key coverage (no missing keys in zh-Hans), interpolation, fallback to en |
| `src/types/` (type guards) | 10 | Type guard functions, discriminated union narrowing, edge-case values |
| Other (`src/utils/`, `src/services/`, etc.) | 5 | Utility functions, service clients |

### Layer 3 (top): Playwright E2E tests — target 30 tests

Runner: Playwright via `tauri-driver` (runs on release PRs only,
~5 minutes per run).

Critical user flows:

| Flow | Tests | Covers |
|---|---|---|
| App launch and first-run | 3 | Window appears, system tray icon, first-run wizard (if any) |
| Config import | 4 | Import from URL, import from file, import from clipboard, malformed config error |
| Proxy switching | 5 | Select node, verify traffic routes, switch node, verify route change, node with no connectivity |
| Mode toggle | 4 | System/proxy/direct/rule toggle, verify OS proxy settings change, persistence across restart |
| Settings | 4 | Open settings, change theme, change language, change port |
| Deep links | 3 | `riptide://` URL handling, import from deep link, invalid deep link error |
| TUN mode | 4 | Enable TUN, verify TUN adapter exists, disable TUN, verify adapter removed |
| Subscription management | 3 | Add subscription, refresh, delete |

### Coverage gate

- **Phase D end**: ≥ 70% line coverage on `core/` (Rust) and
  `services/` (TypeScript). Measured by `cargo llvm-cov` (Rust) and
  `vitest --coverage` (TypeScript).
- Coverage is enforced in CI: a PR that drops coverage below 70% is
  blocked. The gate applies to the **diff**, not the absolute number
  — a PR that adds 100 lines of untested code to a module that was
  at 80% will fail even if the project-wide average is still 70%.
- Coverage does **not** apply to E2E tests (Playwright). E2E tests
  are measured by flow completion, not line coverage.

### Flaky test quarantine

- **Rust**: `#[ignore]` attribute with a mandatory comment explaining
  why and linking to the tracking issue.
- **TypeScript**: `test.skip()` with the same comment/issue pattern.
- **Playwright**: `test.skip()` with the same pattern.
- **Re-evaluation cadence**: every 2 weeks, a CI job lists all
  `#[ignore]` / `test.skip()` tests and fails if any have been
  quarantined for more than 4 weeks without an active tracking issue.
  This prevents quarantine from becoming permanent.

### CI integration

| Layer | Trigger | Duration | Failure behavior |
|---|---|---|---|
| Rust unit tests | Every PR | ~15s | Block merge |
| TypeScript unit tests | Every PR | ~10s | Block merge |
| Playwright E2E | Release PRs only | ~5 min | Block release (not merge) |
| Coverage gate | Every PR | ~30s (on top of unit tests) | Block merge if diff coverage < 70% |

## Consequences

**Enables:**

- A clear, measurable target: 300 + 100 + 30 = 430 tests by Phase D
  end, matching the catchup plan's go criteria.
- The Rust core (highest-risk code) gets the most test coverage (300
  tests, 70% of the pyramid base).
- Fast CI feedback: Rust + TS unit tests run in < 30 seconds on every
  PR. Playwright tests are deferred to release PRs, keeping merge
  velocity high.
- A coverage gate that prevents the test count from growing without
  actually covering new code.

**Costs and trade-offs:**

- **300 Rust tests is a significant investment.** Each test requires
  understanding the module's public API, constructing test fixtures,
  and asserting behavior. The module targets above are approximate;
  some modules will need more tests than listed, others fewer.
- **Playwright on Windows is flakier than on macOS.** WebView2 timing,
  window focus, and system tray interaction are known sources of
  flakiness. Mitigated by: (a) running only on release PRs, (b)
  generous timeouts (5s per assertion), (c) a quarantine mechanism.
- **Coverage gate can be gamed.** Writing trivial tests that exercise
  lines without asserting behavior would inflate coverage. Mitigated
  by code review — reviewers should flag tests that have no `expect`
  / `assert` call.
- **Two coverage tools to maintain.** `cargo llvm-cov` (Rust) and
  `vitest --coverage` (TypeScript) have different coverage semantics
  (line vs branch vs statement). The 70% gate uses **line coverage**
  for both, which is the most conservative metric.

**Forecloses (for now):**

- We do **not** target integration tests (running mihomo or sing-box
  in CI). Integration tests require downloading the sidecar binaries,
  which adds 2-3 minutes to CI and introduces flakiness from binary
  download failures. Integration testing is deferred to the nightly
  `bench.yml` job (see ADR-0007 Phase 3).
- We do **not** target cross-platform test parity (430 Windows tests
  = 631 macOS tests). The macOS suite includes XCUITest UI tests that
  have no direct Playwright equivalent (e.g. macOS-specific system
  tray behavior, Keychain integration). The Windows pyramid focuses
  on Windows-specific behavior.
- We do **not** adopt property-based testing (e.g. `proptest` for
  Rust, `fast-check` for TypeScript) for the initial 430-test target.
  Property-based testing is valuable for config parsing and URI
  serialization but adds complexity. Deferred to Phase E (post-v2.5.0).

**Follow-up actions:**

1. Set up `cargo llvm-cov` in CI (`ci.yml`) with a 70% line coverage
   gate on `core/`. Report coverage as a PR comment.
2. Set up `vitest --coverage` in CI with a 70% line coverage gate on
   `src/stores/`, `src/hooks/`, `src/lib/`, `src/components/`.
3. Set up Playwright + `tauri-driver` in a separate `e2e.yml` workflow
   that runs only on release PRs.
4. Add a `scripts/list-quarantined-tests.sh` script that greps for
   `#[ignore]` and `test.skip()` and fails if any have been
   quarantined > 4 weeks.
5. Track progress against the 430-target in the catchup plan's Phase D
   go criteria checklist.

**References:**

- [`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §9 Phase
  D go criteria — the 430-test target this ADR formalises.
- ADR-0008 (`0008-windows-webview2-test-loader.md`) — the
  `comctl32.dll` DELAYLOAD fix that unblocked the first Rust tests.
- ADR-0009 (`0009-windows-scm-service-vs-user-helper.md`) — the TUN
  service that requires its own test module (`tests/tun_service_*.rs`).
- ADR-0010 (`0010-windows-singbox-integration.md`) — the sing-box
  integration that requires `tests/singbox_*.rs`.
