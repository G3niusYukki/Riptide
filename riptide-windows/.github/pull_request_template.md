<!--
Thanks for contributing to riptide-windows!

This template is a checklist. Replace each section with the relevant
context. The CI workflows (`.github/workflows/ci.yml`,
`.github/workflows/lint.yml`) read the Conventional Commits prefix in
your final commit message to drive auto-labeling, so keep that prefix
correct.
-->

## Summary

<!-- One paragraph: what does this PR change and why? -->

## Type of change

<!-- Tick exactly one. If multiple, file separate PRs. -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing
      functionality to change)
- [ ] Refactor (no behavior change, no new feature)
- [ ] Documentation (AGENTS.md, README, CHANGELOG, ADRs)
- [ ] CI / build (workflows, scripts, toolchain pins)
- [ ] Test (adding or fixing tests only)

## Affected area

<!-- Tick all that apply. -->

- [ ] `riptide-windows/src/` (React + TypeScript UI)
- [ ] `riptide-windows/src-tauri/src/` (Rust backend)
- [ ] `riptide-windows/src-tauri/tauri.conf.json` or
      `riptide-windows/src-tauri/Cargo.toml` (Tauri config / dependency
      bumps)
- [ ] `riptide-windows/package.json` (frontend deps / scripts)
- [ ] `riptide-windows/.github/workflows/` (CI)
- [ ] Documentation only
- [ ] Other (describe below)

## Tauri minor version

<!-- Tauri 2 requires the JS and Rust minor versions to agree.
     If you bumped either side, you MUST bump the other.
     See riptide-windows/AGENTS.md § 5. -->

- [ ] I did **not** touch `package.json` `@tauri-apps/api`, `Cargo.toml`
      `tauri`, or `Cargo.toml` `tauri-build`
- [ ] I bumped the Tauri minor and updated **both** sides
      (`package.json`, `Cargo.toml`, `Cargo.lock`)

## Testing

- [ ] `cd riptide-windows && npm run test` passes locally
- [ ] `cd riptide-windows && npm run tsc -- --noEmit` is clean
- [ ] `cd riptide-windows/src-tauri && cargo test` passes locally
- [ ] `cd riptide-windows/src-tauri && cargo clippy --all-targets -- -D warnings` is clean
- [ ] `cd riptide-windows/src-tauri && cargo fmt --all -- --check` is clean
- [ ] Manual test: (describe what you clicked / ran if UI-affecting)

## Checklist

- [ ] My code follows the conventions in `riptide-windows/AGENTS.md`
      (paths via `WindowsDirs`, `serde_yaml::Value` for YAML edit,
      `Result<T, String>` at Tauri boundary, `tracing` for logs)
- [ ] I added or updated tests for any behavior change
- [ ] I added or updated `CHANGELOG.md` under the next unreleased
      version (call it out in the PR description if not)
- [ ] I read the
      [Windows Catchup Plan](https://github.com/MetaCubeX/riptide/blob/master/docs/WINDOWS-CATCHUP-PLAN.md)
      and confirmed this work matches its current Phase
- [ ] I requested a review from the relevant rein
      (`rust-engineer` / `frontend-engineer` / `qa` / `doc-writer`)

## Risk & rollback

<!-- One or two sentences: what could break, and how do we revert? -->

## Screenshots / logs

<!-- Attach UI screenshots or paste relevant log lines. Delete this
     section if not applicable. -->
