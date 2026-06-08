# Development

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| **Node.js** | 20 LTS+ | [nodejs.org](https://nodejs.org/) |
| **Rust** | 1.75+ stable | [rustup.rs](https://rustup.rs/) — `rustup default stable` |
| **MSVC Build Tools** | VS 2022 | Visual Studio Build Tools → workload "Desktop development with C++" |
| **WebView2** | Ships with Win 11 | Auto-installed on Win 10 via Tauri bootstrapper |
| **WiX Toolset** | 3.x | Downloaded automatically by Tauri for MSI bundling |
| **NSIS** | 3.x | Downloaded automatically by Tauri for NSIS bundling |

::: warning
If `cargo build` fails with `link.exe not found`, the MSVC toolchain is not on `PATH`. Open the "x64 Native Tools Command Prompt for VS 2022" or run `vcvars64.bat` before invoking Cargo.
:::

## Clone & Setup

```powershell
cd riptide-windows

# JS dependencies — pinned via package-lock.json
npm ci

# Verify Rust toolchain
cargo --version    # must be >= 1.75
rustc --version

# Rust dependencies (auto-fetched on first build)
cargo check --manifest-path src-tauri/Cargo.toml
```

## Development Loop

```powershell
# Single command — starts Vite HMR + Tauri dev mode
npm run tauri dev
```

`npm run tauri dev` triggers `beforeDevCommand: "npm run dev"` internally, so a single command is enough. If you want separate Vite logs, run `npm run dev` in a second terminal.

## Type-Checking & Building

```powershell
# TypeScript type-check (no emit)
npm run tsc

# Frontend production build (Vite)
npm run build

# Rust check (fast, no codegen)
cargo check --manifest-path src-tauri/Cargo.toml

# Full production build → NSIS + MSI bundles
npm run tauri build
```

`npm run tauri build` produces:

```
src-tauri/target/release/riptide.exe
src-tauri/target/release/riptide-tun-service.exe
src-tauri/target/release/bundle/nsis/Riptide_<version>_x64-setup.exe
src-tauri/target/release/bundle/msi/Riptide_<version>_x64_en-US.msi
```

## Running Tests

```powershell
# Rust unit + integration tests
cargo test --manifest-path src-tauri/Cargo.toml

# Single test suite
cargo test --manifest-path src-tauri/Cargo.toml --test mihomo_bootstrap

# Single module
cargo test --manifest-path src-tauri/Cargo.toml --lib core::mode_coordinator

# Frontend unit tests (vitest)
npm run test
```

## Lint & Format

```powershell
# Rust
cargo fmt --manifest-path src-tauri/Cargo.toml --all -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings

# TypeScript / ESLint / Prettier
npm run lint            # eslint
npm run format:check    # prettier --check .
npm run format          # prettier --write .
```

CI fails on any of: clippy warning, rustfmt diff, `tsc` error, ESLint warning, prettier diff, or vitest failure.

## Tauri Minor Version Alignment

::: danger Critical Rule
The Tauri 2 contract requires the **JS `@tauri-apps/api` package and the Rust `tauri` crate to share the same minor version**. If they drift, IPC bindings desync and `tauri build` either panics or silently produces a crash-prone bundle.
:::

| File | Field | Required value |
|---|---|---|
| `package.json` | `dependencies."@tauri-apps/api"` | `"~2.10"` |
| `package.json` | `devDependencies."@tauri-apps/cli"` | `"^2"` |
| `src-tauri/Cargo.toml` | `dependencies.tauri` | `"=2.10"` |
| `src-tauri/Cargo.toml` | `build-dependencies.tauri-build` | `"=2.10"` |
| `src-tauri/Cargo.toml` | `dependencies.tauri-plugin-*` | `"=2.10"` (all plugins) |

**Rules:**

1. **Never** change just one side. A Tauri bump is a 4-file edit (package.json, package-lock.json, Cargo.toml, Cargo.lock).
2. **Never** loosen `tauri = "=2.10"` to `"2"` or `"^2"`.
3. Run the full test + build matrix before tagging a release after a Tauri bump.

## YAML Editing Convention

When modifying profile YAML in the Rust backend, always round-trip through `serde_yaml::Value` — never deserialize into a typed struct first. This preserves unknown keys from subscription providers:

```rust
// CORRECT — preserves unknown keys
let mut doc: serde_yaml::Value = serde_yaml::from_str(&input)?;
doc["tun"] = serde_yaml::to_value(&tun_block)?;
let merged = serde_yaml::to_string(&doc)?;

// WRONG — drops keys not in the struct
let mut parsed: ClashRawConfig = serde_yaml::from_str(&input)?;
parsed.tun = Some(tun_block);
let merged = serde_yaml::to_string(&parsed)?;
```
