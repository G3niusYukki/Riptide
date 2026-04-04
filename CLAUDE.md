# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Riptide is a macOS proxy client built with Swift 6, integrating the [mihomo](https://github.com/MetaCubeX/mihomo) core for production-grade proxy and TUN mode support. The app provides a native SwiftUI interface for managing proxy configurations and switching between System Proxy and TUN modes.

**Key Integration:** Riptide does not implement proxy protocols itself. Instead, it:
1. Generates Clash-compatible YAML configurations
2. Manages the mihomo process lifecycle (via privileged helper for TUN mode)
3. Controls mihomo via its REST API (external controller)

## Build & Test Commands

```bash
swift build                                    # Build all targets
swift test                                     # Run all tests (233 tests)
swift test --filter "Mihomo"                   # Run mihomo-related tests
swift run riptide --help                       # CLI usage (legacy)
swift run RiptideApp                           # Run SwiftUI app
./Scripts/download-mihomo.sh                   # Download mihomo binary
```

Requires macOS 14+ and Swift 6.2+ (Xcode 16+).

## Architecture

### Targets

| Target | Purpose |
|--------|---------|
| `Riptide` | Core library: config parsing, mihomo integration, XPC |
| `RiptideHelper` | Privileged helper tool (SMJobBless) - runs as root to launch mihomo |
| `RiptideApp` | SwiftUI app with menu bar UI |

### mihomo Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RiptideApp (SwiftUI)                    │
│  ┌─────────────────┐  ┌─────────────────────────────────┐ │
│  │ Config/Proxy UI│  │ ModeCoordinator                 │ │
│  │                 │  │  - System Proxy / TUN switching │ │
│  └────────┬────────┘  └──────────┬──────────────────────┘ │
│           │                       │                        │
│           └───────────────────────┘                        │
│                           │                               │
│              ┌──────────────▼──────────────┐                │
│              │   MihomoRuntimeManager    │                │
│              │   (actor - main orchestrator)│               │
│              │   - Config generation       │                │
│              │   - XPC to helper           │                │
│              │   - REST API client         │                │
│              └──────────────┬──────────────┘                │
└─────────────────────────────┼───────────────────────────────┘
                              │
              ┌───────────────▼───────────────┐
              │     RiptideHelper (root)      │  ← SMJobBless installed
              │   /Library/PrivilegedHelperTools/  │
              └───────────────┬───────────────┘
                              │ XPC
              ┌───────────────▼───────────────┐
              │         mihomo (root)         │
              │   - TUN device (gVisor)       │
              │   - Proxy protocols           │
              │   - REST API :9090            │
              └───────────────────────────────┘
```

### Core Components

#### 1. MihomoConfigGenerator
Transforms `RiptideConfig` to mihomo-compatible YAML.

**Location:** `Sources/Riptide/Mihomo/MihomoConfigGenerator.swift`

Key features:
- YAML escaping for security (prevents injection)
- Support for all proxy types: SS, VMess, VLESS, Trojan, Hysteria2
- Proxy groups: select, url-test, fallback, load-balance
- TUN configuration (conditional based on mode)

#### 2. MihomoRuntimeManager
Main orchestrator for mihomo lifecycle.

**Location:** `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift`

Responsibilities:
- Directory setup (`~/Library/Application Support/Riptide/mihomo/`)
- Config generation and atomic write (with backup)
- XPC communication with RiptideHelper
- REST API health checks and retries
- Runtime state management

#### 3. HelperToolConnection
Manages XPC connection to privileged helper.

**Location:** `Sources/Riptide/XPC/HelperToolConnection.swift`

Key features:
- `isHelperInstalled()` - checks SMJobBless registration
- `launchMihomo()` / `terminateMihomo()` - process control
- `@unchecked Sendable` wrappers for XPC types

#### 4. SMJobBlessManager
UI-facing manager for helper installation.

**Location:** `Sources/RiptideApp/SMJobBlessManager.swift`

Uses `SMJobBless` API to install helper with admin password prompt.

#### 5. ModeCoordinator
Coordinates between System Proxy and TUN modes.

**Location:** `Sources/Riptide/AppShell/ModeCoordinator.swift`

- System Proxy mode: sets macOS system proxy to mihomo's mixed-port
- TUN mode: launches helper, mihomo manages TUN device directly

### Concurrency Model

- **Swift 6 strict concurrency** enforced throughout
- **Actors** for stateful components:
  - `MihomoRuntimeManager` - main orchestrator
  - `HelperToolConnection` - XPC state
  - `MihomoAPIClient` - API client with URLSession
  - `ModeCoordinator` - mode transitions
  - `ProfileStore` - profile persistence
- **Sendable** conformance for all value types
- `@unchecked Sendable` for `NSXPCConnection` and `NSXPCListener` (Foundation types)

### File System Layout

```
~/Library/Application Support/Riptide/
├── mihomo/
│   ├── config.yaml              # Current mihomo config
│   ├── config.yaml.bak          # Backup of previous config
│   ├── cache/
│   │   ├── GeoIP.dat            # GeoIP database
│   │   └── GeoSite.dat          # GeoSite database
│   └── logs/
│       └── mihomo.log           # mihomo stdout/stderr
├── profiles/                    # Saved user profiles
└── ...

/Library/Application Support/Riptide/
└── mihomo                       # Installed mihomo binary (by helper)
```

## Key Workflows

### 1. Starting TUN Mode

1. User clicks "Start" with TUN mode selected
2. `ModeCoordinator` checks helper installation
3. If not installed, show `HelperSetupView` (SMJobBless prompt)
4. `MihomoRuntimeManager.start(mode: .tun, profile:)`:
   - Generate config with `tun.enable: true`
   - Write config atomically (backup old)
   - Connect to helper via XPC
   - `launchMihomo(configPath:mode:)`
   - Initialize `MihomoAPIClient`
   - Health check with retries (10 attempts, 500ms delay)
5. TUN device created by mihomo, traffic intercepted

### 2. Starting System Proxy Mode

1. Generate config with `tun.enable: false`
2. Launch mihomo (helper optional - can run as user)
3. Wait for API ready
4. `SystemProxyController.enable(httpPort: 6152)` sets macOS proxy
5. Apps route through `127.0.0.1:6152`

### 3. Switching Proxies

1. User clicks proxy node in UI
2. `MihomoRuntimeManager.switchProxy(to: name)`
3. `MihomoAPIClient.switchProxy(to: name, inGroup: "GLOBAL")`
4. PUT request to `http://127.0.0.1:9090/proxies/GLOBAL`
5. mihomo switches active proxy immediately

## Important Implementation Details

### YAML Escaping (Security)

`MihomoConfigGenerator` uses `yamlEscape()` for all user-provided strings:

```swift
private static func yamlEscape(_ string: String) -> String {
    // Detect special YAML characters
    let specialChars = CharacterSet(charactersIn: "#\"'{}[]\n,&*?|<>!=%@")
    if string.rangeOfCharacter(from: specialChars) == nil {
        return string
    }
    // Escape and wrap in quotes
    var escaped = string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
```

This prevents YAML injection attacks from malicious config inputs.

### XPC Protocol

```swift
@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func launchMihomo(configPath: String, mode: String, reply: @escaping (Error?) -> Void)
    func terminateMihomo(reply: @escaping (Error?) -> Void)
    func getMihomoStatus(reply: @escaping (Data?, Error?) -> Void)
    func installMihomo(binaryPath: String, reply: @escaping (Error?) -> Void)
}
```

Note: Must be `@objc` for NSXPC interoperability. Helper tool implements this protocol.

### Path Validation (Security)

Helper tool validates all paths are within allowed directories:

```swift
static func isValidConfigPath(_ path: String) -> Bool {
    let allowedPaths = [
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Riptide/mihomo").path
    ]
    return allowedPaths.contains { path.hasPrefix($0) }
}
```

This prevents the helper from accessing arbitrary files as root.

## Conventions

- All model types: `struct`/`enum` with `Equatable, Sendable, Codable`
- Error types: `enum` with `Error, Equatable, Sendable`
- No force unwraps; strict failure behavior
- Actor isolation for mutable shared state
- Dependency injection via constructors
- TDD: Write tests before implementation

## Known Limitations

1. **Helper Tool Signing**: Requires valid Apple Developer Team ID in `RiptideHelper/Resources/Info.plist` for production use
2. **First Launch**: TUN mode requires one-time admin password for SMJobBless installation
3. **macOS Only**: TUN mode uses macOS-specific NetworkExtension and SMJobBless APIs

## References

- [mihomo documentation](https://wiki.metacubex.one/)
- [SMJobBless sample code](https://developer.apple.com/library/archive/samplecode/SMJobBless/)
- [Clash configuration format](https://github.com/Dreamacro/clash/wiki/configuration)
