# D3 — Service Mode route

Date: 2026-06-02
Status: Accepted
Deciders: @G3niusYukki

## Context

Today, Riptide's TUN mode requires the user to enter their admin
password every time the helper launches (via `SMJobBless`). This is
the "P0 Service Mode" gap from the competitive analysis: Surge and
Stash use Apple's Network Extension framework, which **installs once
and runs as a system extension** without repeated password prompts.

The existing `RiptideHelper` uses `SMJobBless`, which Apple
**deprecated in macOS 13** in favor of `SMAppService`. We need to
pick a path forward that:
- Removes the repeated password prompt (P0 from competitive gap)
- Survives across macOS releases (we currently require macOS 14+)
- Doesn't break the existing "Launch at Login" LaunchAgent

This ADR picks the route Riptide will take for Service Mode.

## Considered Options

### Option A: SMAppService.daemon with privileged helper

- Migrate `RiptideHelper` from `SMJobBless` to
  `SMAppService.daemon(plistName:)`. The helper becomes a
  launchd-managed daemon registered via a `.plist` in
  `/Library/LaunchDaemons/`.
- Once installed (one-time password prompt), the helper
  auto-starts on system boot and survives user logout.
- Swift app talks to helper via XPC (unchanged from today).
- **Pros:**
  - **One-time password prompt**, not per-launch
  - launchd handles restart-on-crash for free
  - Apple-recommended modern API; `SMJobBless` is deprecated
  - Works on macOS 13+ (we already require 14+, so no compat hit)
- **Cons:**
  - Requires re-architecting the helper: must conform to
    `SMAppService.daemon` lifecycle (different from
    `SMJobBlessTool`)
  - Helper binary must be re-signed with a stable Team ID
    (we have this constraint already; not a regression)
  - Debugging launchd daemons is harder than foreground helpers

### Option B: Pure LaunchAgent in `~/Library/LaunchAgents/`

- Drop the privileged helper entirely. Run a long-lived Swift
  process in user space, installed via LaunchAgent.
- That process owns mihomo/sing-box sidecar lifecycle and the
  TUN interface (via the user's `utun` driver, not Network Extension).
- **Pros:**
  - **No admin password ever** — LaunchAgent is per-user, no
    privilege escalation needed
  - Easy to install/uninstall (just a `.plist`)
  - Easy to debug (`launchctl list`, `log stream`)
- **Cons:**
  - **Cannot install a real TUN device** in user space on macOS.
    TUN requires either Network Extension (system) or a
    privileged helper. Workarounds (e.g. `utun` from
    `tun/tap` open-source) are unstable and not Apple-blessed.
  - Dies on user logout — no true "Service Mode"
  - Loses the system-proxy-guard feature (which currently lives
    in the helper)
- **Note:** This option was historically attractive (ClashX
  pre-Network-Extension used it) but is **not viable** in 2026.

### Option C: Network Extension (Surge / Stash model)

- Adopt `NEPacketTunnelProvider` (the same approach Surge and
  Stash use). Install via System Extension entitlement.
- Drop the `RiptideHelper` entirely.
- **Pros:**
  - **Zero password prompts** after the initial System Extension
    approval in System Settings → Privacy & Security
  - Modern, Apple-blessed; matches what every competitor does
  - No helper to maintain
- **Cons:**
  - Requires the
    `com.apple.developer.networking.networkextension` entitlement
    (currently commented out in `Riptide.entitlements`)
  - Entitlement requires a paid Apple Developer account with the
    Network Extensions capability enabled (we have this; see
    CLAUDE.md "Known Limitations")
  - Requires migrating the entire TUN stack from gVisor
    (mihomo sidecar) to Swift in-NE-tunnel (the existing
    `RiptideTunnel/PacketTunnelProvider.swift` is a scaffold,
    not production)
  - **Multi-week migration**; not realistically completable
    inside SP-1 timeframe
  - Loses the Swift Engine ↔ mihomo hotswap (NE tunnels own
    the full TUN device; can't easily delegate to mihomo)

## Decision

**Option A: SMAppService.daemon with privileged helper**, as a
**bridge** until Option C (Network Extension) is feasible. The
rationale is:
- It removes the per-launch password prompt (the user-visible
  complaint)
- It uses Apple's current recommended API (SMAppService, not
  SMJobBless)
- It does not require re-doing the entire TUN stack
- It is a stepping stone: when we eventually migrate to NE
  (Option C), the SMAppService helper can either be repurposed
  (as the "background updater" + "sidecar manager") or removed
  cleanly. Its XPC surface is small and well-isolated.

The **exit criterion** for revisiting this decision is: the
moment we are ready to commit to Option C (Network Extension),
we delete Option A and move. Until then, Option A is a strict
improvement over the status quo.

## Consequences

**Enables:**
- P0: TUN starts without password prompt after first install
- P0: Helper auto-restarts on crash (launchd handles it)
- P0: Survives user logout (helper keeps running as root)
- Existing XPC interface (`HelperToolProtocol`) is unchanged
  → no app-side rewrite

**Forecloses:**
- We do not get the deep NE-integration features (per-app
  routing via NEFilterDataProvider, etc.) until Option C ships
- We still depend on the helper binary being signed with a
  stable Team ID (already required)

**Follow-up actions:**
- T+1: Spike a `RiptideHelper` build that registers via
  `SMAppService.daemon`. Verify the install/upgrade/uninstall
  flow.
- T+2: Update `Scripts/setup-signing.sh` if SMAppService
  requires additional signing flags (it does not, but verify).
- T+3: Document the one-time install UX in
  `docs/INSTALL.md` — users should see a single "Install Helper"
  button in onboarding, not repeated prompts.
- T+6: Re-evaluate Option C in 6 months; if we have engineering
  bandwidth for the NE migration, delete the SMAppService helper
  and switch.

**Risks:**
- Apple's `SMAppService` API has had rough edges in early
  macOS 13.x releases. We're on macOS 14+, so this should be
  fine, but track any reports.
- The first install still requires a password (one-time). Users
  who skip onboarding may not understand. Mitigation: the
  Diagnostics screen will show "Helper: not installed" with a
  one-click install button.
- A buggy helper that crashes in a tight loop could spam
  launchd. Mitigation: helper must implement
  `disable()` cleanly on first error and surface the error to
  the app via XPC.
