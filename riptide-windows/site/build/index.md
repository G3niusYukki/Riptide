# Build & Release

## Version Bump

Riptide Windows shares the `vX.Y.Z` tag with macOS. The version must be kept in sync across four files:

| File | Field |
|---|---|
| `.version` | Canonical version (top-level) |
| `package.json` | `version` |
| `src-tauri/tauri.conf.json` | `version` |
| `src-tauri/Cargo.toml` | `package.version` |
| `CHANGELOG.md` | New `## [X.Y.Z] — YYYY-MM-DD` entry |

Use the automated script:

```powershell
# from the repo root
./Scripts/bump-version.ps1 2.4.2
```

The script updates all four files in lockstep and fails if any file was not edited together (diff-check). The macOS equivalent is `Scripts/bump-version.sh`.

## CI Workflows

Three GitHub Actions workflows live under `riptide-windows/.github/workflows/`:

### `ci.yml` — Continuous Integration

**Triggers:** PR + push to `master` + manual

Runs on `windows-latest` with a 15-minute timeout. Steps:

1. Checkout (full history)
2. Setup Node 20 with npm cache
3. Setup Rust stable with rustfmt + clippy
4. `npm ci` (locked install)
5. `cargo fmt --all -- --check`
6. `cargo clippy --all-targets -- -D warnings`
7. `cargo test --all --no-fail-fast`
8. `npm run tsc -- --noEmit`
9. `npm run test` (vitest)

Target wall time: **< 12 minutes**.

### `release.yml` — Tag-Driven Release

**Triggers:** `v*.*.*` tag push + manual `workflow_dispatch`

Two jobs:

1. **`build`** — matrix `windows-latest × [x64, arm64]` with `fail-fast: false`. Runs `npm ci` → `npm run tauri build` → uploads NSIS + MSI artifacts per architecture.

2. **`publish`** — runs on `ubuntu-latest`. Downloads both arch artifacts, computes `SHA256SUMS.txt`, and creates a GitHub Release via `softprops/action-gh-release@v2`. Prerelease detection is automatic for tags containing `alpha`, `beta`, or `rc`.

Target wall time: **< 25 minutes per architecture**.

### `lint.yml` — Fast Pre-Merge Feedback

**Triggers:** PR only

Runs the lint stack without `cargo test` or `vitest`:

1. `cargo fmt --all -- --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `npm run tsc -- --noEmit`
4. `npx eslint . --max-warnings=0`
5. `npx prettier --check .`

Target wall time: **< 5 minutes**.

## Release Flow

```
bump-version.ps1 → commit → tag vX.Y.Z → git push --follow-tags
                                              │
                                              ▼
                                     release.yml triggered
                                              │
                                    ┌─────────┴─────────┐
                                    ▼                   ▼
                               build (x64)         build (arm64)
                                    │                   │
                                    ▼                   ▼
                               NSIS + MSI          NSIS + MSI
                                    │                   │
                                    └─────────┬─────────┘
                                              ▼
                                     publish (ubuntu)
                                              │
                                              ▼
                                     GitHub Release
                                     + SHA256SUMS.txt
```

### Manual Build for Local QA

```powershell
git checkout vX.Y.Z
cd riptide-windows
npm ci
npm run tauri build
# Artifacts land in src-tauri/target/release/bundle/{nsis,msi}/
```

## NSIS + MSI Bundling

Tauri produces two installer formats in a single build:

| Format | Produced file | Characteristics |
|---|---|---|
| **NSIS** | `Riptide_<version>_x64-setup.exe` | Per-user install to `%LOCALAPPDATA%`; supports custom install dir; foundation for auto-updater |
| **MSI** | `Riptide_<version>_x64_en-US.msi` | System-wide install to `Program Files`; enterprise-friendly; supports `msiexec /i ... /qn` silent install |

Both installers:
- Copy `riptide.exe`, `riptide-tun-service.exe`, and `wintun.dll`
- Register file associations for `.yaml` / `.yml` (optional)
- Create Start Menu shortcuts

WiX (MSI) and NSIS are downloaded automatically by Tauri during the build. Ensure corporate proxies allow downloads from `https://github.com/nicehash/` (WiX) and `https://nsis.sourceforge.io/` (NSIS).

## Tauri Signing Keypair

Tauri 2's auto-updater requires an ed25519 signing keypair:

```powershell
# Generate a new keypair
npm run tauri signer generate -- -w ~/.tauri/riptide.key

# Output:
#   Public key: <base64>
#   Private key written to: ~/.tauri/riptide.key
```

Configuration in `src-tauri/tauri.conf.json`:

```json
{
  "plugins": {
    "updater": {
      "pubkey": "<base64 public key>"
    }
  }
}
```

CI secrets:
- `TAURI_SIGNING_PRIVATE_KEY` — PEM-encoded private key (set as GitHub Actions secret)
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — passphrase for the private key (if set)

::: warning
Until the signing keypair is generated and pinned, the in-app update check opens the browser to GitHub Releases instead of auto-installing. This is the expected behavior during Phase A–C development.
:::

## Cache Strategy

All three CI workflows share a cache key family for Rust artifacts (`Swatinem/rust-cache`) and npm (`actions/cache` keyed on `package-lock.json`). A warm cache from `lint.yml` is reusable by `ci.yml` and `release.yml` on the same runner type.
