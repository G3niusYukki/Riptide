# ADR-0008: Windows test binary DLL loader — delayload `comctl32.dll`

> **Status:** Accepted · **Date:** 2026-06-07 · **Deciders:** rust-engineer
>
> **Note on title**: the original report described the failure as
> "WebView2Loader.dll not loadable". The actual root cause is
> `comctl32!TaskDialogIndirect` (transitive via `tauri` → `muda` →
> `windows-sys` 0.60). The file slug is kept as
> `0008-windows-webview2-test-loader.md` to match the plan task
> filename; the body of this ADR documents the real fault and fix.

## Context

`cargo test --lib` on this Windows 11 dev box (and any other host
where `%SystemRoot%\System32\comctl32.dll` is the v5 5.82 build rather
than the v6.0+ Common Controls) aborts the lib test binary at process
startup with `STATUS_ENTRYPOINT_NOT_FOUND` (0xC0000139). The binary
never reaches `libtest`; every test in the `riptide_windows_lib` test
suite appears as "did not run" with a Windows error dialog. This has
been blocking:

- **B1.1** — 18 URI parser tests
- **B1.2** — 11 Logbook tests (5 paths + 3 store + 3 writer)
- All future Rust `cargo test --lib` suites from Phase B onward (D1,
  D2, D3, etc.)

The `#[cfg(not(test))]` isolation in `lib.rs` (commit `fcf388e`,
"apply cfg(not(test)) isolation to fix Windows test binary") was
necessary but **not sufficient**. The test binary still links the
`tauri` rlib, which pulls in `muda` v0.17.2 (via the
`tray-icon` feature), which in turn pulls in `windows-sys` 0.60.
`windows-sys` 0.60 declares an FFI binding to
`comctl32!TaskDialogIndirect`, and the Rust linker emits a regular
(non-delay) import for that symbol into every binary that links the
`riptide_windows_lib` rlib — including the test binary, even though
no test code calls into muda's menu surface.

`comctl32.dll` is a Windows **Known DLL**: at process startup, the
loader looks in `System32` first and binds to that copy. On a host
where `System32\comctl32.dll` is the v5 build, the loader binds the
v5 copy and cannot resolve `TaskDialogIndirect` (which was added in
v6.0). The v6 build *is* present in this host under
`C:\Windows\WinSxS\amd64_microsoft.windows.common-controls_*\comctl32.dll`,
but Known-DLL resolution wins over WinSxS for `comctl32.dll`, so the
v6 copy is never consulted.

Production `tauri build` and `cargo build --release` are unaffected
because the production `.exe` does not need a strict import contract
on `TaskDialogIndirect` for its own use (muda's tray menu code
constructs the symbol lazily and the production binary links the
**release** profile with the manifest-redirected SxS `comctl32.dll`
when the bundled `app.manifest` requests Common Controls v6). The
test binary is built with the default (v5-compatible) manifest and
no SxS hint, so the strict import surfaces.

## Candidate matrix

| # | Approach | Change surface | Risk | Picked? |
|---|----------|----------------|------|---------|
| 1 | **Delayload `comctl32.dll`** via `.cargo/config.toml` rustflags (`/DELAYLOAD:comctl32.dll /DEFAULTLIB:delayimp.lib`) | 1 new file (`riptide-windows/src-tauri/.cargo/config.toml`, 44 lines incl. rationale) | None for production (loader resolves on first call; production code calls `TaskDialogIndirect` lazily via muda and the SxS v6 copy is found at call time). None for test (test harness never invokes muda). | **Yes** |
| 2 | Add a `<dependentAssembly>` SxS hint to an `app.manifest` to redirect to v6 `comctl32.dll` | New `app.manifest`, wire it into build.rs via `embed_manifest()` or `tauri.conf.json` `bundle.windows.embedManifest` | Larger blast radius — affects production binary; not all Tauri 2 patches propagate the manifest correctly; SxS redirect is finicky with installer bundling | No |
| 3 | Build a stub `comctl32.dll` with `__declspec(dllexport) TaskDialogIndirect` returning E_NOTIMPL and prepend it to `PATH` at test time | New DLL + build.rs + `cargo run --target` wrapper | Adds a build artifact; risk of accidentally shipping the stub; PATH hijack is a CI footgun | No |
| 4 | `cargo test --lib --target x86_64-pc-windows-msvc` plus an env var `RUSTFLAGS="..."` in CI | One-line `ci.yml` change (and dev env vars) | Per-host RUSTFLAGS in `ci.yml` is brittle; it does not help local `cargo test`; cargo's own `.cargo/config.toml` is the canonical place | Partial — would still be a hack |
| 5 | Downgrade `windows-sys` to 0.52 (the version that pre-dates the `TaskDialogIndirect` binding) via `[patch.crates-io]` | `Cargo.toml` patch, full `cargo update` | Could break `tauri` 2.10 / `muda` 0.17.2 which depend on `windows-sys` 0.60; version-mixing `windows-sys` in a Tauri 2 tree is known to cause subtle FFI mismatches | No |
| 6 | Switch to `wry`'s `webview2-com` direct binding instead of `tauri::tray-icon` | Refactor tray menu off `tauri` → custom Win32 + remove muda | Huge blast radius; not on the Phase C roadmap; would invalidate the Phase A tray work | No |
| 7 | Remove `tray-icon` feature from `tauri` (Cargo.toml `features = []`) | One-line `Cargo.toml` change | Loses the entire tray-icon feature; tray is a Phase A deliverable; deferred-to-v2.5.0 tray replacement is not in this plan | No |
| 8 | Stricter `#[cfg(not(test))]` isolation in every Tauri re-export site (deeper than the current `lib.rs` gates) | Many source files, fragile | Already verified to be insufficient — muda's compiled object files emit imports regardless of whether the riptide code references them | No |

**Decision: option 1 (DELAYLOAD comctl32.dll via `.cargo/config.toml`)**.

## Decision

Add `riptide-windows/src-tauri/.cargo/config.toml` with the following
content (the rationale block in the file mirrors this ADR):

```toml
[target.x86_64-pc-windows-msvc]
rustflags = "-C link-arg=/DELAYLOAD:comctl32.dll -C link-arg=/DEFAULTLIB:delayimp.lib"

[target.aarch64-pc-windows-msvc]
rustflags = "-C link-arg=/DELAYLOAD:comctl32.dll -C link-arg=/DEFAULTLIB:delayimp.lib"
```

Why this is safe and minimal:

- **No source change.** No `lib.rs`, `main.rs`, or any `core/` /
  `cmds/` / `config/` file is modified. Only Cargo's link command
  gains two extra flags.
- **No production impact.** The DELAYLOAD resolver looks up
  `comctl32.dll` via the standard loader search order
  (`System32` → `KnownDLLs` → manifest-redirected SxS) at the moment
  the first `comctl32!` symbol is called. In production, muda's tray
  menu code constructs `TaskDialogIndirect` lazily, so the SxS v6
  copy (or, in the v5 case, an early-return fallback) is found at
  call time. The CI `windows-latest` runner ships v6
  `comctl32.dll` in `System32`, so production is also a non-issue.
- **Test harness safe.** The test binary links the same rlib; the
  loader defers the symbol lookup; the test runner never calls into
  muda's menu code, so the unresolved import is never probed.
- **`delayimp.lib` provides `__delayLoadHelper2`**, the symbol MSVC
  requires when a binary uses DELAYLOAD. Forgetting the
  `/DEFAULTLIB:delayimp.lib` flag would cause a link error; both
  flags are paired.
- **Scope is the package only.** The `.cargo/config.toml` lives at
  `riptide-windows/src-tauri/.cargo/config.toml`, which is the
  package-local config directory. It applies to `riptide-windows`
  rlib + binaries only; the rest of the monorepo is unaffected.

## Consequences

### Verification

After landing this change, all of the following must be true:

1. `cargo check --manifest-path riptide-windows/src-tauri/Cargo.toml
   --tests` exits 0 (no new errors or warnings introduced).
2. `cargo test --manifest-path riptide-windows/src-tauri/Cargo.toml
   --lib --no-run` exits 0 and produces
   `target/debug/deps/riptide_windows_lib-*.exe`.
3. `cargo test --manifest-path riptide-windows/src-tauri/Cargo.toml
   --lib core::logbook::paths` runs and reports `7 passed; 0 failed`.
   (This is the smallest non-trivial test module with no transitive
   Tauri surface; it is the task's named acceptance gate.)
4. `cargo build --manifest-path riptide-windows/src-tauri/Cargo.toml
   --release` exits 0 (the DELAYLOAD flags do not regress the
   release build).
5. The Windows installer / NSIS / MSI bundle, which is built via
   `npm run tauri build`, still produces both `riptide.exe` and
   `riptide-tun-service.exe` without link errors.

### Known limitations

- **Production-side risk surface**: if any future `riptide-windows`
  feature ever calls `TaskDialogIndirect` synchronously during app
  startup (before the manifest-redirected SxS v6 `comctl32.dll` has
  a chance to load), the same `STATUS_ENTRYPOINT_NOT_FOUND` would
  surface in the production binary. To date, the only caller is
  muda's tray menu, which is constructed lazily. The release CI does
  not exercise this path. A future hardening step would be to
  `LINK /ERRORREPORT:PROMPT` during release builds or to add a
  smoke test that launches the production `riptide.exe` and
  dismisses the tray menu once.
- **No effect on non-MSVC targets**: the rustflags only apply to
  `*-pc-windows-msvc`. The `*-pc-windows-gnu` target is not
  supported on this crate (no Tauri 2 GNU build pipeline yet) and
  the Mac/Linux targets are unaffected.
- **This is a project-scoped cargo config, not user-scoped.** Other
  Rust crates checked out as siblings of `riptide-windows/src-tauri`
  do not pick up this file. That is the desired behavior — we do
  not want to globally DELAYLOAD `comctl32.dll` for unrelated
  crates.
- **First-time setup gotcha**: a fresh clone must not run
  `git clean -fdx` in `riptide-windows/src-tauri/` without first
  re-creating `.cargo/config.toml` (or restoring it from git). The
  file is committed starting with this ADR's matching commit; older
  `git clean` workflows that exclude `src-tauri/` entirely are fine.

### Future work (out of scope for this ADR)

- Consider switching to `windows-sys = "0.59"` upstream or a muda
  release that drops the `TaskDialogIndirect` import. Tracked in
  follow-up issue (none filed yet — file when Phase B is complete).
- Consider adding a `tauri::Builder::default().setup(...)` smoke
  test that runs against the release binary, so the production
  DELAYLOAD path is exercised in CI. Out of scope for B1.1 / B1.2.
- Once `tauri` 2.10.x ships a tray-icon that does not transitively
  import `TaskDialogIndirect` (e.g. by checking the OS version at
  compile time and using `LoadLibraryW("comctl32.dll")` at runtime),
  revisit whether DELAYLOAD is still needed.
