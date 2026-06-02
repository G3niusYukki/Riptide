# Contributing to Riptide

Thanks for your interest in contributing! Riptide is a cross-platform proxy
client (macOS Swift + Windows/Linux Rust/Tauri) sharing the same
Clash-compatible profile format.

## Code of Conduct

Be respectful. Assume good intent. Keep discussions technical.

## Development Setup

### macOS (Swift)

- **Requirements**: macOS 14+, Swift 6.2+ (Xcode 16+)
- Build: `swift build`
- Test: `swift test` (529 tests in 85 suites)
- Run app: `swift run RiptideApp`
- Lint: `swiftlint` (enforced in CI)

### Windows / Linux (Rust + Tauri)

- **Requirements**: Node 22+, Rust 1.75+
- Dev mode: `cd riptide-windows && npm install && npm run tauri dev`
- Lint: `npx tsc --noEmit` + `cargo check`

## Architecture

```
Sources/Riptide/         — Core library (protocols, transport, DNS, rules, config)
Sources/RiptideApp/      — SwiftUI macOS app
Sources/RiptideCLI/      — CLI tool
Sources/RiptideTunnel/   — NetworkExtension (TUN)
riptide-windows/         — Windows/Linux Tauri app (React + Rust)
```

See `CLAUDE.md` for the full component map.

## Concurrency Rules

### Swift (macOS)

- **Swift 6 strict concurrency is enforced.**
- Use `actor` (not `class` + locks) for all stateful components.
- Value types (`struct`, `enum`) must be `Sendable, Equatable, Codable`.
- `@unchecked Sendable` is allowed **only** on `NSXPCConnection` / `NSXPCListener`.
- No `DispatchQueue.async { [weak self] }` — use `Task { await actor.method() }`.

### Rust (Windows/Linux)

- Prefer `tokio::sync::Mutex<T>` over `std::sync::Mutex`.
- Tauri commands are `async fn` returning `Result<T, String>`.
- Avoid `.unwrap()` in production paths — use `?` or `.context()`.

## Pull Request Process

1. **Branch**: Create from `master` — use `feature/<name>` or `fix/<name>`.
2. **Build & test**: `swift build` must be zero-warning; `swift test` must pass
   (XCTest + Swift Testing + UI tests).
3. **UI changes**: update `A11yID` identifiers and add/extend the matching
   `RiptideAppUITests` case.
4. **Lint**: `swiftlint --strict` (Swift) + `cargo fmt --check` + `cargo clippy` (Rust).
5. **PR description**: What / why / how tested. Link related issues.
6. **Review**: At least one maintainer approval required before merge. CI must
   be green on the PR branch.
7. **Rebase, don't merge**: rebase onto `master` before merging — never merge
   `master` into your feature branch.
8. **Commit style**: Squash-merge to master. See **Git 提交规范** below.

### Commit message format

We follow [Conventional Commits](https://www.conventionalcommits.org/).
See **Git 提交规范** below for the full type list and examples.

## Git 提交规范

参考 [Conventional Commits](https://www.conventionalcommits.org/),常用前缀:

- `feat:` 新功能(用户可见)
- `fix:` bug 修复
- `refactor:` 重构(无新功能,无 bug 修复)
- `perf:` 性能优化
- `test:` 仅测试(新增/修改测试,无生产代码变更)
- `docs:` 仅文档(`*.md`、`*.txt`、注释)
- `chore:` 杂项(清理、依赖、`AGENTS.md`、归档)
- `build:` 构建系统(`Package.swift`、`entitlements`、脚本)
- `ci:` CI/发布工作流(`.github/workflows/`)

格式:

```text
<type>(<scope>)<!:>: <imperative summary ≤72 chars>

<body — 解释 why,而不是 what。>

<footer — 引用 issue / breaking change>
```

- 标题用祈使语气、不要大写开头、不要句号结尾。
- `<scope>` 可选,推荐: `dns`、`rules`、`protocol`、`transport`、`mitm`、
  `tunnel`、`ui`、`cli`、`windows`、`linux`。
- 破坏性变更:在 type 后加 `!`,并在 footer 写 `BREAKING CHANGE: <说明>`。

## PR 流程

1. Fork → 新分支(`feature/xxx` 或 `fix/xxx`)。
2. `swift build` 零警告。
3. `swift test` 全部通过(XCTest + Swift Testing + UI 测试)。
4. 如修改 UI,更新 `A11yID` 常量并补充/扩展 `RiptideAppUITests` 用例。
5. PR 描述:为什么做、改了什么、如何测试、关联 issue。
6. 等待 CI 全绿(`.github/workflows/ci.yml` 全部 job: `swift-lint`、
   `swift-build-test`、`swift-ui-test`、`frontend-check`、`rust-check`、
   `linux-check`)+ 至少 1 个 maintainer review。
7. **不要 merge master 到你的分支** — rebase,不要 merge。

## 不要做

- ❌ 不要提交 `fatalError` / `preconditionFailure`(已经存在的 `assertionFailure`/`Swift.fatalError` 视情况)
- ❌ 不要新增 `@unchecked Sendable` — 留给 senior review 后决定
- ❌ 不要直接删除公开 API — 先 `@available(*, deprecated, ...)` 一个发布周期
- ❌ 不要 merge `master` 进 feature 分支(rebase)
- ❌ 不要把 secrets / 订阅 URL / MITM 私钥写入仓库或日志
- ❌ 不要在 `Riptide.swift` 里堆逻辑(模块入口,只放公共 surface)
- ❌ 不要悄悄引入 silent fallback — 显式失败更好

## Release 流程

发布通过 `git tag` 触发,**不要**手动 `git push --tags` 之外的发布操作。

1. **准备 release 分支**
   - 从 `master` 切 `release/x.y.z`
   - 更新 `CHANGELOG.md`:把 `## [x.y.z-dev] — Unreleased` 重命名为
     `## [x.y.z] — YYYY-MM-DD`
   - 运行 `Scripts/bump-version.sh x.y.z`(同步 `.version` 与 `Info.plist`)
2. **PR & merge**
   - 提交 PR,review 通过后 squash-merge
   - `master` HEAD commit 即为发布 commit
3. **打 tag → 触发 `.github/workflows/release.yml`**
   - `git tag vx.y.z && git push origin vx.y.z`
   - workflow 会并行构建 **macOS**(universal binary + DMG,Apple 签名/公证条件具备时执行)、
     **Windows**(MSI + NSIS)和 **Linux**(deb + AppImage)
   - 所有 artifact 汇聚后由 `softprops/action-gh-release` 创建 GitHub Release,
     自动生成 SHA256 校验和
4. **Homebrew tap 同步**
   - `homebrew.yml` 在 release `published` 事件后自动更新
     `G3niusYukki/homebrew-tap` 仓库的 `Formula/riptide.rb`
5. **Sparkle appcast**
   - macOS 用户通过内置 Sparkle 收到更新通知(stable/beta 渠道见
     `UpdateSettingsView`)
   - Tag 形如 `v1.2.3-beta1` 时,`release.yml` 会把该 release 标记为 prerelease

### Hotfix 流程

紧急修复:`fix/<scope>-<issue>` 分支 → 单独 PR → merge 后打 patch tag
(例:`v3.0.1`),跳过完整 release 分支。

## Reporting Bugs

Use GitHub Issues. Include:

- Riptide version (`RiptideApp → About` or `.version`)
- OS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (sanitized — remove IPs/keys)

## Security

- **Do not** commit API keys, tokens, or certificates.
- For vulnerability reports, contact maintainers directly instead of opening a public issue.
- MITM CA keys and subscription credentials are stored in the system Keychain — never in config files.

## License

By contributing, you agree that your contributions will be licensed under the
MIT License covering this project.
