# riptide-windows/AGENTS.md

> Project context for any agent (human contributor, CI bot, or AI assistant)
> working in the **`riptide-windows/`** subtree. This file is a Windows-only
> subset of the top-level `AGENTS.md`; it is authoritative **for Windows
> work** but it deliberately omits macOS-specific sections (Swift code,
> NetworkExtension, SMJobBless, etc.). When the two disagree, the top-level
> `AGENTS.md` wins on shared concerns, and this file wins on Windows-specific
> tooling/path/automation concerns.
>
> **Roadmap context**: this file ships as part of Phase A of
> [`../docs/WINDOWS-CATCHUP-PLAN.md`](../docs/WINDOWS-CATCHUP-PLAN.md) — the
> 12-week plan to bring Windows to parity with macOS v2.4.1. The catchup
> plan is the source of truth for _what_ is being built; this file is the
> source of truth for _how_ to build it on Windows.

---

## 1. Project Scope

`riptide-windows/` is the **Windows-native Tauri 2 port** of Riptide. It
wraps the [mihomo](https://github.com/MetaCubeX/mihomo) Clash-YAML proxy
core (the same one macOS uses as a sidecar) and ships a React/TypeScript
UI on top of a Rust backend. It produces **two binaries** in every
release:

- `riptide.exe` — the Tauri UI app (user-elevation, no admin needed for
  the UI itself).
- `riptide-tun-service.exe` — a minimal Windows service that runs mihomo
  as `SYSTEM` so that the TUN interface works without per-launch UAC
  prompts.

### In scope

- System-proxy mode and TUN mode (TUN via mihomo's gVisor stack on
  top of the `wintun` driver; the driver DLL ships in the installer).
- Clash YAML profile management (CRUD, import by URL / share URI / file,
  active profile persistence, subscription scheduler).
- Routing (rules + GeoIP/GeoSite auto-download), DNS policy overlay,
  WebDAV sync, kill switch, region presets, partial TLS tricks.
- Diagnostics report, recovery watchdog (sleep/wake + network change
  events), global hotkeys, system tray, deep-link `riptide://` scheme.
- Distribution: **NSIS** and **MSI** bundles via `tauri build`; in Phase D,
  WinGet / Chocolatey / Scoop manifests are layered on top.

### Explicitly **out** of scope (do not propose or build in this repo)

- **iOS** — top-level AGENTS.md marks iOS as out for v3.0.0.
- **Linux desktop packaging** — `cargo check` is built in CI for Linux
  to keep the platform code compiling, but no `.deb` / AppImage is
  produced. The `platform/*_linux.rs` files exist only to keep the Rust
  crate buildable on a Linux host.
- **macOS code** — Swift, Xcode, NetworkExtension, SMJobBless,
  TouchBarProvider, Apple Shortcuts, WidgetKit — none of that lives
  here. See the top-level `AGENTS.md` § 4–5.
- **A standalone Rust in-process proxy engine** — Windows is mihomo +
  sing-box only (see `../docs/decisions/0007-windows-kernel-router.md`).
  The pure-Swift engine on macOS has no Windows equivalent.
- **Re-doing the TUN stack as a custom driver** — we depend on mihomo's
  gVisor netstack + `wintun.dll`. Custom NDIS / WFP drivers are not on
  the roadmap.

### Cross-platform parity rule

If a feature ships on macOS but is missing on Windows, the default
expectation is that **Phase B/C of the catchup plan will port it**.
The catchup plan is the priority list; do not silently leave parity
gaps by inventing a Windows-only shortcut.

---

## 2. Environment & Toolchain

| Item             | Value                                       | Notes                                                                                                                    |
| ---------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Windows version  | **Windows 10 1809+**                        | WebView2 is required; Win 7 is not supported and the installer does not ship an offline WebView2 bootstrapper.           |
| Node.js          | **20 LTS or newer**                         | `package.json` scripts assume Node 20+. `engines` is not currently enforced — fix it before bumping.                     |
| Rust toolchain   | **1.75+** stable                            | `cargo --version` must be ≥ 1.75. Use `rustup default stable`; do not pin to a specific patch unless CI is broken.       |
| Tauri            | **2.10.x** (both JS and Rust)               | The JS and Rust minor versions **must agree** — see § 5.                                                                 |
| WebView2         | shipped with Win 11; bootstrapper on Win 10 | Configured via `tauri.conf.json → bundle.windows.webviewInstallMode = "downloadBootstrapper"`.                           |
| MSVC build tools | required for Rust on Windows                | Install via the Visual Studio Build Tools 2022 workload "Desktop development with C++".                                  |
| WiX Toolset      | 3.x                                         | Required for MSI bundling. Tauri downloads WiX automatically; ensure corporate proxies do not block the GitHub download. |
| NSIS             | 3.x                                         | Required for NSIS bundling. Tauri downloads NSIS automatically.                                                          |

> **First-time setup gotcha**: if `cargo build` fails with `link.exe not
found`, the MSVC toolchain is not on `PATH`. Open the "x64 Native Tools
> Command Prompt for VS 2022" or run `vcvars64.bat` before invoking
> Cargo.

---

## 3. Repository Layout (this subtree only)

```
riptide-windows/
├── AGENTS.md                    # this file
├── CHANGELOG.md                 # Windows-side changelog (Phase A A1.4)
├── README.md                    # user-facing landing page
├── package.json                 # @tauri-apps/api pinned to ~2.10
├── package-lock.json
├── tsconfig.json / tsconfig.node.json
├── vite.config.ts
├── index.html
├── public/                      # static assets served as-is
├── src/                         # React + TypeScript UI
│   ├── main.tsx / App.tsx
│   ├── App.css                  # Tailwind entry
│   ├── components/              # Dashboard, Proxies, Profiles, Rules,
│   │                            # Connections, LogViewer, NodeEditor,
│   │                            # Settings/* (Assets, Dns, Gateway,
│   │                            # Network, Recovery, Rewrite, Sync),
│   │                            # Layout, Sidebar, Toast, YamlEditor
│   ├── hooks/                   # useConnections, useProxies, useRules,
│   │                            # useTraffic, useTrafficHistory, useTheme
│   ├── stores/                  # Zustand stores: riptide (global),
│   │                            # toast
│   ├── services/tauri.ts        # the single IPC boundary — every
│   │                            # invoke() goes through here so types
│   │                            # stay in sync with Rust commands
│   ├── i18n/                    # i18next + locales/{zh-CN,en-US,...}
│   ├── lib/yamlAutocomplete.ts  # CodeMirror YAML hint integration
│   ├── styles/tokens.css        # design tokens
│   ├── types/index.ts           # shared TS types
│   └── utils/format.ts
└── src-tauri/                   # Rust backend
    ├── Cargo.toml               # version, deps, default-run = riptide-windows
    ├── tauri.conf.json          # Tauri 2 config, identifier, bundle
    ├── build.rs
    ├── icons/                   # 32 / 128 / @2x / .icns / .ico
    ├── resources/               # mihomo.exe, geosite.dat, geoip.metadb
    ├── src/
    │   ├── main.rs              # thin wrapper, calls lib::run()
    │   ├── lib.rs               # tauri::Builder, command registration
    │   ├── cli.rs               # --install-service / --uninstall-service
    │   ├── bin/tun_service.rs   # SCM-registered service binary
    │   ├── cmds/                # Tauri command handlers (one file per
    │   │                        # area): config, dns, gateway, mode,
    │   │                        # proxy, proxy_editor, rewrite, system,
    │   │                        # webdav, windows
    │   ├── config/              # YAML profile parser, active state,
    │   │                        # DNS policy, profile metadata,
    │   │                        # profiles CRUD, rewrite, rules, share
    │   │                        # URI parser
    │   ├── core/                # mode_coordinator, mihomo (lifecycle),
    │   │                        # mihomo_api (REST client),
    │   │                        # mihomo_bootstrap (download + SHA-256),
    │   │                        # sysproxy, windows_proxy /
    │   │                        # windows_sysproxy, kill_switch,
    │   │                        # recovery_watchdog, region_presets,
    │   │                        # tls_tricks, subscription_scheduler,
    │   │                        # webdav, secrets (DPAPI), warp,
    │   │                        # gateway, tray, geo_assets,
    │   │                        # diagnostics, service / service_linux
    │   ├── platform/            # platform shims: autostart_linux,
    │   │                        # sysproxy_linux, tray_linux,
    │   │                        # tun_linux (no-op / lib-only on Linux)
    │   └── utils/               # dirs, windows_dirs, elevation (UAC
    │                            # relaunch), hotkeys, logger, process
    ├── tests/                   # Phase B: unit + integration tests
    └── target/                  # cargo build output (gitignored)
```

Anything outside `riptide-windows/` (top-level `AGENTS.md`, `Sources/`,
`Tests/`, `Scripts/`, `docs/`, `homebrew/`, `rules/`, `site/`, etc.) is
governed by the top-level `AGENTS.md`, not by this file.

---

## 4. Build, Test & Run

### 4.1 First-time setup

```powershell
# from the repo root
cd riptide-windows

# JS dependencies (pinned via package-lock.json — use ci, not install)
npm ci

# Rust dependencies (auto-fetched on first build)
cargo --version     # must be >= 1.75
rustc --version
```

### 4.2 Development loop

```powershell
# Terminal 1: Vite dev server with HMR
npm run dev

# Terminal 2: Tauri dev mode (launches the app, watches Rust)
npm run tauri dev
```

`npm run tauri dev` triggers `beforeDevCommand: "npm run dev"`, so a
single `npm run tauri dev` is also enough if you don't need to see the
Vite logs separately.

### 4.3 Type-check and build

```powershell
# TypeScript type-check (no emit)
npm run tsc

# Frontend production build (Vite)
npm run build

# Rust check (fast, no codegen)
cargo check --manifest-path src-tauri/Cargo.toml

# Rust release build + NSIS + MSI bundles
npm run tauri build
```

`npm run tauri build` produces:

```
src-tauri/target/release/riptide.exe
src-tauri/target/release/riptide-tun-service.exe
src-tauri/target/release/bundle/nsis/Riptide_<version>_x64-setup.exe
src-tauri/target/release/bundle/msi/Riptide_<version>_x64_en-US.msi
```

### 4.4 Tests

```powershell
# Rust unit + integration tests (Phase B onward)
cargo test --manifest-path src-tauri/Cargo.toml

# Run a single suite
cargo test --manifest-path src-tauri/Cargo.toml --test mihomo_bootstrap
cargo test --manifest-path src-tauri/Cargo.toml --lib core::mode_coordinator

# Frontend unit tests (Phase B onward; vitest + Testing Library)
npm run test
```

**Coverage gate (Phase D)**: aim for ≥ 70% line coverage on
`src-tauri/src/core/` and `src/services/`. Use `cargo-llvm-cov`:

```powershell
cargo llvm-cov --manifest-path src-tauri/Cargo.toml --html --output-dir coverage
```

### 4.5 Lint & format

```powershell
# Rust
cargo fmt --manifest-path src-tauri/Cargo.toml --all -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings

# TypeScript / ESLint / Prettier
npm run lint          # eslint --max-warnings=0
npm run format:check  # prettier --check .
npm run format        # prettier --write .
```

CI (see § 11) fails on any of: clippy warning, rustfmt diff, `tsc`
error, ESLint warning, prettier diff, or vitest failure.

---

## 5. Tauri 2 Minor Version Alignment — DO NOT BREAK THIS

The Tauri 2 contract requires the **JS `@tauri-apps/api` package and the
Rust `tauri` crate to share the same minor version**. If they drift, the
generated IPC bindings desync and `tauri build` either panics at codegen
time or, worse, silently produces a bundle that crashes at runtime.

| File                   | Field                               | Required value (as of v2.4.1)           |
| ---------------------- | ----------------------------------- | --------------------------------------- |
| `package.json`         | `dependencies."@tauri-apps/api"`    | `"~2.10"` (caret-tilde; allows patches) |
| `package.json`         | `devDependencies."@tauri-apps/cli"` | `"^2"` (caret; tracks minor)            |
| `src-tauri/Cargo.toml` | `dependencies.tauri`                | `=2.10` (exact minor pin)               |
| `src-tauri/Cargo.toml` | `build-dependencies.tauri-build`    | `=2.10`                                 |
| `src-tauri/Cargo.toml` | `dependencies.tauri-plugin-*`       | `=2.10` (all eight plugins)             |

**Rules:**

1. **Never** change just one side. A Tauri bump is a 4-file edit
   (package.json, package-lock.json via `npm install`, Cargo.toml,
   Cargo.lock via `cargo update -p tauri`).
2. **Never** loosen `tauri = "=2.10"` to `"2"` or `"^2"`. The Phase A
   bug A1.3 explicitly pinned the minor to prevent Cargo from silently
   pulling 2.11+.
3. When bumping the Tauri minor, run the full matrix in § 4.3 + 4.4
   before tagging a release.
4. CI includes a `tauri-alignment.yml` check (Phase B § 3 B2.3) that
   diffs the JS and Rust minor versions and fails the build on drift.

---

## 6. Path & Filesystem Conventions

### 6.1 Use `WindowsDirs`, never Tauri's bundle path

`src-tauri/src/utils/windows_dirs.rs` is the single source of truth for
runtime paths. **All** persisted state — profiles, logs, geo assets,
DNS policy, mihomo binary, kill-switch state, secrets, WebDAV
config — must live under `%APPDATA%\Riptide\`.

```
%APPDATA%\Riptide\
├── profiles\                      # WindowsDirs::profiles_dir()
│   ├── <name>__<uuid>.yaml
│   └── <name>__<uuid>.meta.json
├── active.json
├── dns_policy.json
├── region_preset.json
├── tls_tricks.json
├── kill_switch.json
├── webdav_config.json             # DPAPI-encrypted password
├── mihomo\                        # WindowsDirs::mihomo_dir()
│   ├── mihomo.exe
│   └── config.yaml                # generated, do not edit
├── logs\                          # WindowsDirs::logs_dir()
│   └── riptide.log.<date>         # daily rolling via tracing-appender
└── geoip.metadb / geosite.dat

%PROGRAMDATA%\Riptide\             # machine-scope (SYSTEM-readable)
└── service.conf                   # SCM service launch params
```

**Hard rule**: never use the bundle identifier
(`com.riptide.app`, from `tauri.conf.json`) for runtime file paths.
Tauri's `path::app_data_dir()` resolves to
`%APPDATA%\com.riptide.app\` which does **not** match `%APPDATA%\Riptide\`
and will silently create a phantom second app data directory the user
can't find via the Start menu. Always call `WindowsDirs::*`.

### 6.2 macOS-style `~/Library/Application Support/` does not exist

Do not translate macOS paths verbatim. The macOS code uses
`~/Library/Application Support/Riptide/...`; the Windows equivalent is
`%APPDATA%\Riptide\...` and the macOS code does not need to change
when the Windows port is updated.

### 6.3 Long-path support

Some users keep deep profile directory trees (e.g. an OneDrive-synced
profiles folder). `WindowsDirs` does not currently enable
`\\?\` long-path prefixes. If a path exceeds MAX_PATH (260 chars), log
a `WARN` and surface a "move Riptide data to a shorter path" hint in
the UI rather than crashing.

---

## 7. YAML Editing — Round-trip via `serde_yaml::Value`

Profile files are Clash YAML. Users edit them in `YamlEditor.tsx`
(CodeMirror), and the Rust backend may need to inject runtime overlays
(TUN block, DNS policy, region preset, TLS tricks) **without losing
unknown keys** the user or a subscription provider added.

### 7.1 The rule

When the Rust backend needs to **modify** a profile YAML (e.g. add a
`tun:` block before handing it to mihomo), parse it with
`serde_yaml::Value` and re-serialize — do **not** deserialize into a
`ClashRawConfig` struct first.

```rust
// CORRECT — preserves unknown keys
let mut doc: serde_yaml::Value = serde_yaml::from_str(&input)?;
doc["tun"] = serde_yaml::to_value(&tun_block)?;
let merged = serde_yaml::to_string(&doc)?;

// WRONG — drops any key not in ClashRawConfig
let mut parsed: ClashRawConfig = serde_yaml::from_str(&input)?;
parsed.tun = Some(tun_block);
let merged = serde_yaml::to_string(&parsed)?;
```

### 7.2 Why this matters

Subscription providers frequently add custom keys (e.g. `script:`, custom
rule providers, experimental `geosite`-style arrays) that mihomo accepts
but our `ClashRawConfig` struct does not model. Deserializing into the
struct silently drops them; the user's node group disappears, or a
custom rule provider stops resolving. Round-tripping via
`serde_yaml::Value` keeps the user's profile byte-stable except for the
fields we intentionally edited.

### 7.3 The single-reader / single-writer pattern

The frontend **only reads** YAML via `get_profile_yaml` and **only
writes** YAML via `update_profile_yaml`. Both routes round-trip through
`serde_yaml::Value` internally so user-authored keys survive
UI-mediated edits. Subscriptions (which are also YAML) go through the
same path on import.

---

## 8. Concurrency & Error Conventions

- **Async runtime**: `tokio` with `features = ["full"]`. All Tauri
  commands are `async fn` returning `Result<T, String>` — the `String`
  payload is what the JS side sees, so map errors at the boundary with
  `.map_err(|e| e.to_string())`.
- **Shared state**: prefer `tokio::sync::Mutex<T>` for async-held state
  and `parking_lot::Mutex<T>` for short synchronous critical sections.
  Do not hold a `std::sync::Mutex` across `.await`.
- **Cross-actor state**: `Arc<StdMutex<T>>` or `Arc<RwLock<T>>` for
  read-mostly data. State that needs to outlive a single command (e.g.
  the active profile, the mode coordinator) lives on `tauri::State<T>`.
- **Tauri commands**: register every command in `lib.rs` via
  `.invoke_handler(tauri::generate_handler![...])`. Do not dynamically
  register commands at runtime.
- **Logging**: use `tracing` (the `info!`, `warn!`, `error!` macros),
  not `println!` or `eprintln!`. `utils/logger.rs` configures
  `tracing-subscriber` with an `EnvFilter` (default `riptide=info`)
  and a daily rolling file appender under
  `WindowsDirs::logs_dir()`. To temporarily increase verbosity for a
  bug report, set the `RUST_LOG=riptide=debug,mihomo=info` env var.
- **Errors**: enum + `thiserror::Error`. Match the macOS style: every
  subsystem exposes a `XxxError` enum that `impl std::error::Error` and
  `impl Display`. Map to user-facing strings at the Tauri boundary.

---

## 9. Release Flow

Windows ships on the same `vX.Y.Z` git tag as macOS. The release
workflow (Phase B § 3 B2.2) builds both platforms and attaches MSI +
NSIS to the GitHub Release alongside the macOS DMG + ZIP.

### 9.1 Version bump

```powershell
# from the repo root
./Scripts/bump-version.ps1 2.4.2
```

`bump-version.ps1` (Phase A § 3 A4) updates the four (currently five)
places in lockstep:

1. `.version` (canonical; top-level read by every bundler)
2. `riptide-windows/package.json` → `version`
3. `riptide-windows/src-tauri/tauri.conf.json` → `version`
4. `riptide-windows/src-tauri/Cargo.toml` → `package.version`
5. `riptide-windows/CHANGELOG.md` → new `## [X.Y.Z] — YYYY-MM-DD` entry
   at the top

It also fails if any of the four files were not edited together
(diff-check). The macOS `bump-version.sh` does the equivalent on the
Swift side.

### 9.2 Tag, push, release

```bash
git add -A
git commit -m "chore: bump version to 2.4.2"
git tag -a v2.4.2 -m "Riptide v2.4.2"
git push origin master --follow-tags
```

The release workflow builds for `windows-latest` on `x64` and `arm64`
matrix, runs `tauri build`, collects the NSIS + MSI artifacts, signs
them (Phase D § 5 D5), and uploads to the GitHub Release created by
the `release.yml` job.

### 9.3 Manual build for local QA

```powershell
git checkout v2.4.2
cd riptide-windows
npm ci
npm run tauri build
# artifacts land in src-tauri/target/release/bundle/{nsis,msi}/
```

---

## 10. Known Limitations

| Limitation                                | Why                                                                      | Workaround                                                                                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Windows 7 not supported**               | Tauri 2 requires WebView2, which Microsoft never shipped for Win 7.      | Document the Win 10 1809 floor in README; the MSI bootstrapper auto-installs WebView2 on Win 10.                                                  |
| **TUN mode requires `wintun.dll`**        | mihomo's gVisor stack depends on the wintun userspace driver.            | Ship `wintun.dll` next to `riptide.exe` and next to `mihomo.exe`; the installer copies both.                                                      |
| **One UAC prompt on first TUN install**   | The SCM-registered service must be installed as `SYSTEM`.                | Show a one-shot "Install TUN Service" button in onboarding; subsequent launches are silent.                                                       |
| **Hotkey conflicts**                      | `Ctrl+Alt+P` and `Ctrl+Alt+M` are popular with other apps.               | `global-hotkey` returns false on conflict; we surface a toast and fall back to UI-only.                                                           |
| **System proxy drift**                    | Other apps (Spotify, OneDrive) reset the WinHTTP proxy.                  | `system_proxy` 3-second drift detector auto-restores. Tunable in `Settings → Network`.                                                            |
| **Auto-updater requires signing keypair** | Tauri 2 mandates `pubkey` in `tauri.conf.json`.                          | Phase D § 5 D5 generates the keypair and wires the CI secret. Until then, the in-app `check_update` opens the browser instead of auto-installing. |
| **`MIHOMO_SHA256` must be filled**        | Empty string disables verification (dev-only).                           | `core/mihomo_bootstrap.rs:35` is the pin; never tag a release with an empty hash.                                                                 |
| **Cargo test platform shim**              | `platform/*_linux.rs` exist to make the crate compile on Linux CI hosts. | They contain no-op or stub implementations; do not call them from non-`#[cfg(target_os = "linux")]` code.                                         |
| **iOS / Linux desktop distribution**      | Explicitly out of scope (top-level AGENTS.md).                           | Linux `cargo check` keeps the crate compiling; no packaging.                                                                                      |

---

## 11. CI Workflows

The Windows subtree ships **three** GitHub Actions workflows under
`riptide-windows/.github/workflows/`. They are intentionally
self-contained: a contributor who clones only `riptide-windows/`
should be able to copy the workflows into a fork and get green
checkmarks on a PR without pulling the rest of the monorepo.

| File          | Triggers                                    | Purpose                                                             | Target wall time    |
| ------------- | ------------------------------------------- | ------------------------------------------------------------------- | ------------------- |
| `ci.yml`      | PR + push to `master` + manual              | Build · lint · test on `windows-latest`                             | **< 12 min**        |
| `release.yml` | `v*.*.*` tag push + manual `inputs.version` | Build NSIS + MSI for `x64` and `arm64`, publish a GitHub Release    | **< 25 min / arch** |
| `lint.yml`    | PR + manual                                 | Fast pre-merge feedback: rustfmt + clippy + tsc + eslint + prettier | **< 5 min**         |

PR descriptions are standardized via
`riptide-windows/.github/pull_request_template.md` — it forces the
contributor to tick the "Tauri minor version" box (see § 5) and the
test/lint boxes that map 1-to-1 onto the steps below.

### 11.1 `ci.yml` — continuous integration

Runs **one** job, `ci`, on `windows-latest` with a 15-minute timeout.
Steps, in order:

1. `actions/checkout@v4` with `fetch-depth: 0` (full git history
   enables changelog tools).
2. `actions/setup-node@v4` (Node 20) with `cache: npm` keyed on
   `riptide-windows/package-lock.json`.
3. `dtolnay/rust-toolchain@stable` (1.75+) with
   `components: rustfmt, clippy`.
4. `Swatinem/rust-cache@v2` with `workspaces:
riptide-windows/src-tauri` and `shared-key: riptide-windows-cargo`
   (shared across `ci.yml`, `release.yml`, `lint.yml`).
5. `npm ci` (locked install — never `npm install`).
6. `cargo fmt --all -- --check`.
7. `cargo clippy --all-targets -- -D warnings`.
8. `cargo test --all --no-fail-fast` (all suites, fail on the first
   failure per suite; keeps the log readable).
9. `npm run tsc -- --noEmit` (TypeScript type-check, no emit).
10. `npm run test` (vitest run).

A `concurrency` block cancels in-flight runs on the same ref so that
pushing twice to the same branch does not queue up a stale run. On
failure, the `target/test-results/` and `target/debug/deps/*.dmp`
artifacts are uploaded for forensic inspection.

> **Why a single job, not a matrix?** Splitting the pipeline across
> jobs costs more in setup time and cache duplication than it saves;
> `windows-latest` is a single SKU. The split between CI and lint
> (below) is the right level of parallelism.

### 11.2 `release.yml` — tag-driven release

Triggers on `v*.*.*` tag push, or via `workflow_dispatch` with a
manual `version` input. The pipeline is **two jobs**:

1. **`build`** — runs in a `windows-latest × [x64, arm64]` matrix with
   `fail-fast: false` so one arch's failure does not silently cancel
   the other. The cross-compile is done by passing
   `targets: ${{ matrix.rust_target }}` to
   `dtolnay/rust-toolchain`. After `npm ci` the job runs
   `npm run tauri build` (which produces both NSIS `.exe` and
   `.msi` bundles) and uploads the bundles to a per-arch
   `upload-artifact@v4` slot keyed on
   `riptide-windows-${{ matrix.arch_label }}-${{ version }}`.

2. **`publish`** — depends on `build`, runs on `ubuntu-latest` (we
   only need the GitHub API and a POSIX shell for `sha256sum`).
   Downloads both per-arch artifacts into `dist/`, flattens them
   into a single tree, computes `SHA256SUMS.txt`, and hands the
   files to `softprops/action-gh-release@v2` with
   `generate_release_notes: true`. Prerelease detection is automatic
   for tags containing `alpha`, `beta`, or `rc`.

The `concurrency` group is `release-${{ github.ref }}` with
`cancel-in-progress: false` — releases are never cancelled, only
superseded by a fresh tag push.

### 11.3 `lint.yml` — fast pre-merge feedback

Triggers on **PR only** (push to `master` is intentionally
excluded — the cheaper `ci.yml` already covers it). Runs the same
lint stack as `ci.yml` but **without** `cargo test` or `vitest`, so
the typical PR gets a green/red lint signal in under five minutes:

1. `cargo fmt --all -- --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `npm run tsc -- --noEmit`
4. `npx eslint . --max-warnings=0`
5. `npx prettier --check .`

`eslint` and `prettier` are pulled in via `npm ci` against the
lockfile; the devDependencies `eslint`, `prettier`,
`@typescript-eslint/parser`,
`@typescript-eslint/eslint-plugin`, `eslint-plugin-react`, and
`eslint-plugin-react-hooks` are pinned in `package.json`. The
configs live at `riptide-windows/.eslintrc.cjs` and
`riptide-windows/.prettierrc` (with a matching `.prettierignore`).

### 11.4 Cache strategy

All three workflows share the same `Swatinem/rust-cache` key
prefix family — `riptide-windows-{ci,lint,release-$arch}` — so a
warm cache from `lint.yml` is reusable by `ci.yml` and
`release.yml` on the same runner type. `npm` cache is keyed on
`riptide-windows/package-lock.json` only; **never** key it on
`package.json` (that defeats the lockfile guarantee).

### 11.5 Tauri signing secrets (release only)

`release.yml` reads two optional secrets:

- `TAURI_SIGNING_PRIVATE_KEY` — PEM-encoded ed25519 key used by
  Tauri's auto-updater.
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — passphrase for the key.

Both are passed only to the `tauri build` step. The actual installer
signing cert (Authenticode) is a Phase D concern; `release.yml` will
grow a `signtool` step once D5 wires the CI secret.

### 11.6 Local reproduction

To mirror CI locally before pushing a PR:

```powershell
cd riptide-windows

# JS deps (use ci, not install, to match CI exactly)
npm ci

# Rust checks
cd src-tauri
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --all
cd ..

# Frontend checks
npm run tsc -- --noEmit
npm run test
npm run lint
npm run format:check
```

If `npm run format:check` fails, run `npm run format` to autofix
most formatting issues locally before pushing.

---

## 12. Pointers to the Catchup Plan

This file is a **how to build** reference. For **what to build and in
what order**, see:

- [`../docs/WINDOWS-CATCHUP-PLAN.md`](../docs/WINDOWS-CATCHUP-PLAN.md) —
  the 12-week, 64-task, ~210-person-day plan that brings Windows to
  parity with macOS v2.4.1 and lays the groundwork for v2.5.0
  (Reality / AnyTLS / sing-box default-on).
- [`../docs/decisions/0005-proxy-engine-protocol.md`](../docs/decisions/0005-proxy-engine-protocol.md)
  — `ProxyEngine` protocol + `EngineRouter` policy (`defaultMihomo`).
- [`../docs/decisions/0006-mihomo-sidecar-version-pin.md`](../docs/decisions/0006-mihomo-sidecar-version-pin.md)
  — mihomo version pin policy (mirrored in
  `core/mihomo_bootstrap.rs::MIHOMO_VERSION`).
- [`../docs/decisions/0007-windows-kernel-router.md`](../docs/decisions/0007-windows-kernel-router.md)
  — sing-box sidecar decision for Windows (the only Windows-specific
  kernel decision; macOS follows the same shape via
  `Sources/Riptide/SingBox/`).
- [`../docs/RELEASE-CHECKLIST.md`](../docs/RELEASE-CHECKLIST.md) —
  cross-platform release checklist (CI + signing + artifacts).
- [`README.md`](./README.md) — Windows-side user-facing landing page,
  with the current Phase status table and Tauri command reference.

If this file and the catchup plan ever disagree, **the catchup plan
wins** for scope/scheduling questions; this file wins for tooling,
paths, and coding-convention questions.

---

## 13. Engine Router (ADR-0005 implementation)

The Windows port of the `ProxyEngine` protocol + `EngineRouter`
decision lives entirely in `src-tauri/src/`:

| File | Responsibility |
|---|---|
| `core/engines/mod.rs` | Module entry; re-exports the public types below. |
| `core/engines/proxy_engine.rs` | `ProxyEngineKind` (Mihomo/Singbox/Swift), `ProxyKind` (11 variants: SS/Vmess/Vless/Trojan/Hy2/Snell/Tuic/Socks5/Http/Reality/AnyTls), `ProxyNode` (engine-agnostic input), `Config { format, body }`, `EngineError`, and the `ProxyEngine` trait (4 methods: `name`, `kind`, `supported_proxy_kinds`, `generate_config`). |
| `core/engines/mihomo_engine.rs` | `MihomoEngine` impl — **zero-sized struct**, does not call into `MihomoManager`. The trait is for the future "import via engine" path; today's mihomo-launching code path is unchanged. |
| `core/engines/router.rs` | `EngineRouter { policy: Mutex<Policy> }`, `Policy { DefaultMihomo, ExplicitSingbox }`. 5 unit tests in `#[cfg(test)] mod tests` cover the ADR-0005 routing table. |
| `cmds/engines.rs` | 6 Tauri commands (see below). |

### 6 Tauri commands (cross-platform, no `#[cfg]`)

| Command | Returns | Purpose |
|---|---|---|
| `engine_current` | `ProxyEngineKind` | Where the router sends a non-forced kind right now. |
| `engine_set_policy` | `Result<(), String>` | Accepts `"default_mihomo"` or `"explicit_singbox"`. |
| `engine_supported_kinds` | `Vec<ProxyKind>` | The currently routed engine's supported kinds. |
| `engine_status` | `EngineStatus { name, kind, version, last_error }` | One-shot health snapshot. |
| `engine_list_kinds` | `Vec<ProxyEngineKind>` | All engines routable on Windows: `[Mihomo, Singbox]`. Swift is excluded (ADR-0007). |
| `engine_get_policy` | `String` | Wire string of the active policy. |

### State wiring

A single `Arc<EngineRouter>` is registered in `lib.rs::run()` via
`tauri::Builder::default().manage(Arc::new(EngineRouter::default_mihomo()))`.
The state is **not** persisted to disk in this revision — a follow-up
phase will surface an `engine_policy.json` (parallel to
`active.json`).

### Adding a new engine

1. Add a variant to `ProxyEngineKind` (e.g. `Xray`).
2. Add a zero-sized `XrayEngine` impl in `core/engines/xray_engine.rs`.
3. Add a routing rule in `EngineRouter::engine_for` (or add a new
   forced-kind branch in the `match kind { ... }` head).
4. Update `engine_list_kinds` and `engine_supported_kinds`'s
   `match` to dispatch to the new impl.
5. Add unit tests in `core/engines/router.rs`.

## 14. Test Binary Loader (`comctl32` DELAYLOAD) — v2.4.1+

> Despite the original report describing the failure as a
> "WebView2Loader.dll" issue, the actual root cause is
> `comctl32!TaskDialogIndirect` (transitive via `tauri` tray-icon →
> `muda` → `windows-sys` 0.60). This section is the running docs
> entry; see
> [`../docs/decisions/0008-windows-webview2-test-loader.md`](../docs/decisions/0008-windows-webview2-test-loader.md)
> for the full candidate matrix and rationale.

### Symptom

On Windows hosts that ship `comctl32.dll` v5 in `%SystemRoot%\System32`
(rather than the v6.0+ Common Controls), `cargo test --lib` aborts at
process startup with `STATUS_ENTRYPOINT_NOT_FOUND` (0xC0000139). The
binary never reaches `libtest`; the test runner reports
"could not start process" and a Windows error dialog flashes. This
blocks every `cargo test --lib` invocation on such a host, including
the 18-test B1.1 URI parser and 11-test B1.2 Logbook suites that this
plan needs to land in Phase B.

### Root cause

`tauri = "=2.10"` with the `tray-icon` feature pulls in `muda`
v0.17.2, which pulls in `windows-sys` 0.60. `windows-sys` 0.60
declares an FFI binding to `comctl32!TaskDialogIndirect`. The Rust
linker emits a **regular** (non-delay) import for that symbol into
every binary that links the `riptide_windows_lib` rlib, including the
test binary, even though no test code ever calls into muda's menu
surface.

`comctl32.dll` is a Windows Known DLL: the loader binds
`System32\comctl32.dll` first. On a v5 host (v5.82), the v5 build
does not export `TaskDialogIndirect` (added in v6.0). The v6 build
*is* present in this host's `WinSxS`, but Known-DLL resolution wins
over WinSxS, so the v6 copy is never consulted.

`#[cfg(not(test))]` isolation in `lib.rs` (commit `fcf388e`) is
necessary but not sufficient — muda's compiled object files emit
imports regardless of whether any of its symbols are called from
riptide code.

### Fix

Add `src-tauri/.cargo/config.toml` with the package-local rustflags:

```toml
[target.x86_64-pc-windows-msvc]
rustflags = "-C link-arg=/DELAYLOAD:comctl32.dll -C link-arg=/DEFAULTLIB:delayimp.lib"

[target.aarch64-pc-windows-msvc]
rustflags = "-C link-arg=/DELAYLOAD:comctl32.dll -C link-arg=/DEFAULTLIB:delayimp.lib"
```

DELAYLOAD defers the `comctl32!TaskDialogIndirect` resolution to
first use; the test harness never invokes muda's menu code, so the
missing entrypoint is never probed. `delayimp.lib` provides the
`__delayLoadHelper2` symbol MSVC requires. The flags are safe for
the production release binary (muda constructs `TaskDialogIndirect`
lazily; the loader finds the SxS v6 `comctl32.dll` at call time).

### Dual-config layout (workspace root + package local)

Since v2.4.1+ the rustflags live at **two** paths:

- `riptide-windows/.cargo/config.toml` — workspace-root copy
- `riptide-windows/src-tauri/.cargo/config.toml` — package-local copy

Both files contain the same `[target.*-pc-windows-msvc]` rustflags.
We need both because Cargo's `.cargo/config.toml` lookup walks the
directory tree **upward from the workdir**; it does not walk down.
Concretely:

| Workdir + invocation                                       | Config that wins        |
| ---------------------------------------------------------- | ----------------------- |
| `cd src-tauri && cargo test`                               | `src-tauri/.cargo/`     |
| `cd riptide-windows && cargo build --manifest-path src-tauri/Cargo.toml --tests` | `riptide-windows/.cargo/` |
| `cd riptide-windows && cargo test` (no manifest flag)      | **none** — error        |

That third row is why we can't just leave the package-local file:
`cargo test` invoked from `riptide-windows/` with no manifest flag
fails with "could not find `Cargo.toml`". Most IDEs and CI scripts
that target the package from the workspace root rely on the
upward-walked file, which is why we ship the workspace-root copy as
the primary path. The package-local copy stays as a defence-in-depth
fallback — if a future contributor runs cargo from
`riptide-windows/src-tauri/` (or any nested directory), the fix
still applies.

Verified empirically: `cd riptide-windows && cargo build
--manifest-path src-tauri/Cargo.toml --tests -v | grep DELAYLOAD`
emits 3 hits (one per rustc invocation: `riptide_windows_lib`,
`tun_service`, `riptide_windows`).

The 4th stanza in each `config.toml` covers the `i686-pc-windows-msvc`
target (the original `4e3800a` had only x86_64 + aarch64). The i686
build is part of the `tauri build` matrix on some hosts and would
have hit the same loader abort.

### Why not hoist the rustflags to the monorepo root

- The `riptide-windows/src-tauri/` subdir is the only Rust crate in
  the monorepo that has this problem (it is the only one that links
  `tauri` with the `tray-icon` feature). macOS, the `riptide-cli`
  binary, and any future sub-crates do not need DELAYLOAD.
- We do not want DELAYLOAD to leak into every Rust crate on the
  contributor's machine via `~/.cargo/config.toml`; it must stay
  scoped to the riptide-windows subtree.
- A future contributor who clones only the `riptide-windows/`
  subtree still gets the fix automatically; no extra setup step is
  needed.

### Verification commands

Run these on a Windows 11 dev box to confirm the fix is in place and
the test binary can boot:

```powershell
# 1. Confirm the test binary builds and the runner can load it
cd riptide-windows
cargo test --manifest-path src-tauri/Cargo.toml --lib --no-run
# Expected: exit 0, prints "Executable unittests src\lib.rs ..."

# 2. Run the smallest non-trivial test module (no Tauri surface)
cargo test --manifest-path src-tauri/Cargo.toml --lib core::logbook::paths
# Expected: 7 passed; 0 failed; 0 ignored

# 3. Run the existing engine-router + lib.rs tests to confirm no regression
cargo test --manifest-path src-tauri/Cargo.toml --lib autostart_passes_minimized_flag
cargo test --manifest-path src-tauri/Cargo.toml --lib core::engines::router
# Expected: 1 + 5 = 6 passed; 0 failed

# 4. Confirm the release build is unaffected
cargo build --manifest-path src-tauri/Cargo.toml --release
# Expected: exit 0
```

If `cargo test --lib --no-run` fails with the same
`STATUS_ENTRYPOINT_NOT_FOUND` (0xC0000139), the most likely cause is
that **both** `riptide-windows/.cargo/config.toml` and
`riptide-windows/src-tauri/.cargo/config.toml` were deleted (e.g.
by `git clean`), or that the rustflags entry is syntactically
invalid in one of them. Restore both files from git
(`git checkout -- riptide-windows/.cargo riptide-windows/src-tauri/.cargo`)
and re-run the verification commands above.

### CI integration

`ci.yml` already runs `cargo test --manifest-path src-tauri/Cargo.toml
--all` (see § 11.1 step 8). With the DELAYLOAD flags in place, the
CI runner (which ships v6 `comctl32.dll` in `System32`) will pass
even on hosts where the link step would otherwise surface a strict
import. No CI workflow change is required; the fix is invisible to
CI.

### Watch out

- **Do not run `git clean -fdx` inside `riptide-windows/src-tauri/`
  without first backing up `.cargo/config.toml`**. The file is
  committed (since the B1.1/B1.2 fix commit), so `git checkout --`
  will restore it — but on a fresh `git clone` of a stale branch
  the file may be missing until you pull the latest `master`.
- **Do not loosen the rustflags to global scope** (e.g. by moving
  the file to `~/.cargo/config.toml`). That would DELAYLOAD
  `comctl32.dll` for every Rust crate you ever build on this host,
  including unrelated projects, and would mask future regressions
  inside `riptide-windows`.
- **Do not switch off the `tray-icon` feature in Cargo.toml** to
  "fix" the loader — the tray menu is a Phase A deliverable. If
  the tray feature is ever dropped, the DELAYLOAD flag becomes
  dead code and should be removed in the same commit.
