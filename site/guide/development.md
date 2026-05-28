# Development

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    RiptideApp (SwiftUI)                   │
│  ┌─────────────────┐   ┌──────────────────────────────┐  │
│  │ Config/Proxy UI │   │ ModeCoordinator (actor)     │  │
│  └────────┬────────┘   │  Swift Engine | mihomo | TUN│  │
│           │            └──────────────────────────────┘  │
│           ▼                                              │
│   ┌──────────────────────────────────────────────────┐   │
│   │  MihomoRuntimeManager (actor — orchestrator)    │   │
│   └──────────────┬───────────────────────────────────┘   │
└──────────────────┼──────────────────────────────────────┘
                   │
       ┌───────────┴────────────┐
       ▼                        ▼
┌──────────────┐        ┌────────────────────┐
│ Swift Proxy  │        │  mihomo sidecar    │
│ Engine       │        │  (REST :9090, TUN) │
│ (built-in)   │        └─────────┬──────────┘
└──────┬───────┘                  │ XPC (root)
       │                ┌─────────▼──────────┐
       └───────────────►│ RiptideHelper       │
                        │ (SMJobBless)        │
                        └─────────────────────┘
```

## Repository Layout

```
.version                            # canonical version
Package.swift                       # macOS SwiftPM manifest
Sources/Riptide/                    # pure-Swift proxy library
  Protocols/  Transport/  DNS/  Rules/  Tunnel/  LocalProxy/
  Mihomo/     XPC/        AppShell/  Subscription/
  Config/     Sync/       MITM/      Scripting/
Sources/RiptideCLI/                 # CLI (ArgumentParser)
Sources/RiptideApp/                 # SwiftUI macOS app
Sources/RiptideTunnel/              # NetworkExtension
Tests/RiptideTests/                 # 53 test suites
riptide-windows/                    # Windows/Linux Tauri app
  src/                              # React + TypeScript
  src-tauri/src/                    # Rust backend
    cmds/  config/  core/  utils/
```

## Module Map

| Module | Path | Role |
|--------|------|------|
| `Riptide` | `Sources/Riptide/` | Core library — protocols, rules, DNS, config, MITM |
| `RiptideCLI` | `Sources/RiptideCLI/` | CLI — start/stop, profile management, diagnostics |
| `RiptideApp` | `Sources/RiptideApp/` | macOS SwiftUI app |
| `RiptideTunnel` | `Sources/RiptideTunnel/` | NetworkExtension packet tunnel |
| `RiptideTests` | `Tests/RiptideTests/` | 53 XCTest suites |
| `riptide-windows` | `riptide-windows/` | Tauri 2 app — React frontend + Rust backend |

## Building

### macOS

```bash
swift build              # Library + CLI + App
swift test               # 53 suites
swift run RiptideApp     # Launch UI
```

Requirements: macOS 14+, Swift 6.2+ (Xcode 16+).

### Windows

```bash
cd riptide-windows
npm install
npm run tauri dev         # Dev mode (hot-reload)
npm run tauri build       # Release bundle
```

Requirements: Node 22+, Rust 1.75+, Windows 10+ with WebView2.

## Concurrency Model

### Swift (macOS)

- **Swift 6 strict concurrency** enforced.
- Stateful components use `actor`: `MihomoRuntimeManager`, `ModeCoordinator`, `ProfileStore`
- Value types: `Sendable, Equatable, Codable`
- `@unchecked Sendable` only on `NSXPCConnection` / `NSXPCListener`

### Rust (Windows/Linux)

- `tokio` for async, `Mutex<T>` / `Arc<StdMutex<T>>` for shared state
- Tauri commands: `async fn` → `Result<T, String>`
- Avoid `.unwrap()` in production paths

## Running Tests

```bash
# All suites (XCTest + Swift Testing)
swift test

# Single suite
swift test --filter "RuleEngine"

# Specific test
swift test --filter "RuleEngine/testDomainRuleMatch"
```

## CI Pipeline

| Job | Runs On | What |
|-----|---------|------|
| SwiftLint | ubuntu-latest | Lint changed `.swift` files |
| Swift Build & Test | macos-15 | `swift build` + `swift test` |
| Frontend Check | windows-latest | `tsc --noEmit` + `vite build` |
| Rust Check | windows-latest | `cargo check` + `cargo test --no-run` |

See `.github/workflows/ci.yml`.

## Adding a New Protocol

1. Create `Sources/Riptide/Protocols/NewProtocol/NewProtocolStream.swift`
2. Implement the `ProxyProtocolStream` protocol
3. Register in `Sources/Riptide/Connection/ProxyConnector.swift`
4. Add config parsing in `Sources/Riptide/Config/ClashConfigParser.swift`
5. Add tests in `Tests/RiptideTests/`

Conform to the existing patterns: `ShadowsocksStream`, `VMessStream`, etc.
