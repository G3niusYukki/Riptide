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
- Test: `swift test` (53 suites)
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
2. **Tests**: Add tests for new behavior. Existing suites must pass.
3. **Lint**: `swiftlint --strict` (Swift) + `cargo fmt --check` + `cargo clippy` (Rust).
4. **PR description**: What / why / how tested. Link related issues.
5. **Review**: At least one maintainer approval required before merge.
6. **Commit style**: Squash-merge to master. Commit message: `area: imperative summary`.

### Commit message format

```
area: short imperative summary (≤72 chars)

Optional body explaining why and what tradeoffs were made.
```

Areas: `protocol`, `dns`, `rules`, `config`, `tunnel`, `ui`, `cli`, `windows`, `linux`, `ci`, `docs`.

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
