# Riptide Module Split — M1.4

This document records the split of `Sources/Riptide/` into two modules
to enable iOS code sharing.

## Split Rationale

- **RiptideCore** — cross-platform logic: protocols, transports, DNS, rules,
  config parsing, MITM, scripting, subscriptions, WebDAV sync, external control.
  Compiles for macOS + iOS (and future platforms).
- **RiptideMac** — macOS-specific plumbing: VPN/NetworkExtension, XPC helper
  integration, mihomo lifecycle, TUN bridge, local proxy server, app shell
  (ModeCoordinator, ProfileStore), system proxy control.

## File Migration Map

### → Sources/RiptideCore/ (cross-platform)

| Source | Target |
|--------|--------|
| `Protocols/` | `Protocols/` |
| `Transport/` | `Transport/` |
| `DNS/` | `DNS/` |
| `Rules/` | `Rules/` |
| `Config/` | `Config/` |
| `Models/` | `Models/` |
| `Connection/` | `Connection/` |
| `Subscription/` | `Subscription/` |
| `MITM/` | `MITM/` |
| `Scripting/` | `Scripting/` |
| `Sync/` | `Sync/` |
| `Control/` | `Control/` |
| `NodeEditor/` | `NodeEditor/` |

### → Sources/RiptideMac/ (macOS-only)

| Source | Target |
|--------|--------|
| `VPN/` | `VPN/` |
| `XPC/` | `XPC/` |
| `AppShell/` | `AppShell/` |
| `Mihomo/` | `Mihomo/` |
| `Tunnel/` | `Tunnel/` |
| `LocalProxy/` | `LocalProxy/` |
| `SingBox/` | `SingBox/` |

## Dependency Graph After Split

```
RiptideCore  (no macOS deps — pure Swift + Network.framework + CryptoKit)
     ↑
RiptideMac   (depends on RiptideCore + NetworkExtension + XPC + CoreWLAN)
     ↑        ↑
RiptideApp   RiptideCLI   RiptideTunnel
```

For iOS: `RiptideApp_iOS` → `RiptideCore` + `RiptideTunnel_iOS` (no `RiptideMac`).

## Migration Steps

1. Create `Sources/RiptideCore/` and `Sources/RiptideMac/` directories
2. Move files per the migration map above
3. Update `Package.swift` targets (see `Package.swift.next`)
4. Update `import Riptide` → `import RiptideCore` in moved files
5. Add `import RiptideMac` in RiptideMac files that reference each other
6. Run `swift build` and fix compilation errors
7. Run `swift test` (53 suites must pass)
8. Verify RiptideApp launches correctly

## Rollback Plan

If the split causes unresolvable issues:
- `git revert` the migration commit
- All moved files return to `Sources/Riptide/`
- `Package.swift` reverts to single-target layout
