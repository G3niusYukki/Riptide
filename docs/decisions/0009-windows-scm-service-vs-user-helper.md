# ADR-0009: Windows SCM service vs user-level helper for privileged TUN operations

> **Status:** Accepted · **Date:** 2026-06-08 · **Deciders:** maintainers

## Context

On macOS, Riptide uses `SMJobBless` to install a privileged XPC helper
(`RiptideHelper`) that runs as root. The helper owns TUN device creation,
route table manipulation, and DNS interception — operations that require
elevated privileges on every platform. The helper is installed once by the
main app, starts on demand via XPC, and is managed by `launchd`.

Windows has no XPC equivalent. Two shapes are viable:

1. **SCM-registered Windows service** (`riptide-tun-service.exe`) running
   as `SYSTEM`. Installed once via `sc create`, starts/stops via the
   Windows Service Control Manager (SCM). Runs in session 0, isolated
   from the user desktop. Communicates with the main app via a named
   pipe or localhost gRPC.

2. **User-level helper** (`riptide-tun-helper.exe`) launched with UAC
   elevation (`ShellExecuteW` with `runas` verb). Runs in the user's
   session, visible in Task Manager as a child of the main process.
   Requires a UAC consent dialog **every time** TUN mode starts,
   because Windows does not persist UAC elevation grants across process
   lifetimes.

The Windows catchup plan
([`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3 A3)
designates `riptide-tun-service.exe` as the privileged component. This
ADR formalises the choice and documents the trade-offs.

## Decision

**Windows uses an SCM-registered service (`riptide-tun-service.exe`)
running as SYSTEM for all privileged TUN operations.**

The service binary is a standalone Rust executable produced by the same
`Cargo.toml` workspace as the main app. It is installed once during
first-run setup:

```
sc create RiptideTunService binPath= "\"%PROGRAMFILES%\Riptide\riptide-tun-service.exe\"" start= demand DisplayName= "Riptide TUN Service"
```

Lifecycle:

- **Start**: the main app calls `sc start RiptideTunService` (or the
  Rust equivalent via `windows-service` crate) when the user enables
  TUN mode. The service starts on demand, binds a named pipe at
  `\\.\pipe\riptide-tun`, and begins accepting commands.
- **Stop**: the main app calls `sc stop RiptideTunService` when the
  user disables TUN mode or quits the app. The service tears down
  the TUN adapter and exits cleanly.
- **Crash recovery**: the service registers with SCM using
  `SERVICE_AUTO_START` recovery (restart on failure, 30-second delay,
  reset failure count after 60 seconds of clean operation). SCM
  handles the restart; no watchdog code is needed in the main app.
- **Uninstall**: `sc delete RiptideTunService` removes the service
  registration. The main app calls this during uninstall.

IPC protocol (named pipe):

- The service listens on `\\.\pipe\riptide-tun` with a JSON-over-pipe
  protocol (same shape as the macOS XPC interface: `{"cmd":"create_tun","adapter_name":"riptide0",…}`).
- The main app connects as a client. Commands are synchronous
  request/response. The pipe is ACL'd to `BUILTIN\Users` read/write
  so any user session can connect, but only SYSTEM can create the pipe.

Why not a user-level helper:

- **UAC prompt on every launch.** Windows UAC does not persist
  elevation grants. Every time the user toggles TUN mode, they see a
  consent dialog. This is a deal-breaker for a proxy app that toggles
  TUN frequently (mode switches, profile changes, network changes).
- **Session 0 isolation.** A service running in session 0 is not
  affected by user logoff, lock-screen, or Fast User Switching. A
  user-level helper dies when the user logs off, breaking TUN for
  remote desktop or multi-user scenarios.
- **No tray-icon dependency.** The service binary has no UI
  dependency (no WebView2, no tray-icon, no `comctl32.dll`). It links
  only `windows-service`, `tokio`, and the TUN adapter library. This
  avoids the DELAYLOAD workaround from ADR-0008 entirely.

## Consequences

**Enables:**

- One UAC prompt on first install. After that, TUN mode starts and
  stops without user interaction.
- SCM-managed lifecycle: reliable restart on crash, clean shutdown on
  system reboot, no zombie processes.
- Service binary is small (~2 MB, no WebView2 dependency) and easy to
  sign with an EV code-signing certificate (required for kernel-mode
  TUN driver loading on Windows 10+).
- Clean separation: the service owns only TUN/route/DNS operations;
  the main app owns UI, config, and proxy kernel management.
- macOS-to-Windows parity: `SMJobBless` (macOS) ↔ `sc create`
  (Windows) are the same shape — privileged helper, IPC channel,
  managed lifecycle.

**Costs and trade-offs:**

- **First install requires elevation.** The main app must run
  `sc create` with admin privileges. This happens once, during the
  installer (NSIS/MSI runs elevated by default). If the user skips
  the installer and runs the portable build, the first TUN attempt
  triggers a UAC prompt to install the service.
- **Service binary must be signed.** Unsigned services are blocked by
  Windows Defender Application Control (WDAC) on managed endpoints.
  The build pipeline must EV-sign `riptide-tun-service.exe` with the
  same certificate used for the main app.
- **Uninstall requires `sc delete`.** The NSIS/MSI uninstaller must
  call `sc delete RiptideTunService` before removing files. If the
  uninstaller fails (e.g. service is stuck), the user must manually
  run `sc delete RiptideTunService` from an elevated prompt.
- **Named pipe security.** The pipe ACL must be set correctly — too
  permissive (Everyone full control) is a local privilege escalation
  vector; too restrictive (SYSTEM only) blocks the main app from
  connecting. The `BUILTIN\Users` read/write ACL is the standard
  pattern for per-user IPC to a SYSTEM service.
- **Session 0 UI restrictions.** The service cannot show any UI
  (message boxes, dialogs). All errors must be communicated via the
  pipe protocol and surfaced by the main app. This is the correct
  design for a background service, but it means the service's logs
  must be written to the Windows Event Log or a file, not `stdout`.

**Forecloses (for now):**

- We do **not** use a COM out-of-process server (LocalServer) as the
  privileged component. COM registration complexity and the need for
  a manifest with `requestedExecutionLevel` make it heavier than a
  plain service for no benefit.
- We do **not** use a scheduled task running as SYSTEM. Scheduled
  tasks are harder to manage at runtime (no clean stop/restart
  surface) and have weaker security semantics than SCM services.
- We do **not** ship a kernel-mode TUN driver (WinTun/WireGuard-NT
  kernel driver) as part of the service binary. The driver is
  installed separately by the NSIS/MSI installer with its own
  elevation prompt. The service loads the driver at runtime via
  `CreateFileW` on the device node.

**Follow-up actions:**

1. `riptide-windows/src-tauri/src/service/` — implement the service
   binary: `main.rs` (service entry point),
   `pipe_server.rs` (named pipe listener), `tun_manager.rs` (TUN
   adapter create/delete/route table).
2. `riptide-windows/src-tauri/src/core/tun_service_client.rs` — IPC
   client in the main app: connect to pipe, send commands, handle
   timeouts and reconnection.
3. NSIS/MSI installer — add `sc create` / `sc delete` commands to
   the install/uninstall scripts. Add service binary to the signed
   files list.
4. Tests: `tests/tun_service_lifecycle.rs` (install, start, stop,
   uninstall), `tests/tun_service_pipe.rs` (command round-trip,
   timeout, malformed input), `tests/tun_service_recovery.rs`
   (kill service, verify SCM restarts it).

**References:**

- macOS `RiptideHelper` (`RiptideHelper/Sources/HelperTool.swift`) —
  the privileged helper this ADR mirrors on Windows.
- ADR-0007 (`0007-windows-kernel-router.md`) — the mihomo/sing-box
  router that runs in the main app and sends commands to the service.
- ADR-0008 (`0008-windows-webview2-test-loader.md`) — the
  `comctl32.dll` DELAYLOAD workaround that the service binary avoids
  entirely (no Tauri/WebView2 dependency).
- [`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3 A3 —
  the implementation plan for the TUN service (2 person-days).
