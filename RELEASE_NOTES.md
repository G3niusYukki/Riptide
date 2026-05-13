# Riptide v1.5.0 — TUN Mode Official

**Release Date:** 2026-05-13

## ✨ Highlights

TUN mode is now **stable and recommended for unsigned builds**. No Apple Developer account required for full traffic interception.

## ✨ New Features

- **TUN mode official**: removed Beta label, deleted `tunUnavailable` dead code (05dd963)
- **TUN recovery hardening**: max 3 retries with exponential backoff 2s→4s→8s; stops monitor after exhaustion (1ddf63f)
- **Dynamic TUN interface detection**: scans all utun devices for mihomo gVisor IP range instead of hardcoding `utun120` (8b1885b)
- **Forceful termination detection**: detects hung mihomo process in XPC helper path during stop (8b1885b)
- **TUN recovery events**: recovery exhaustion errors now surface to ModeCoordinator and UI via `setEventHandler` protocol (617d80c)
- **System proxy guard visibility**: `guardUnavailable` event warns users when System Proxy guard is unavailable without helper (7416888)
- **Onboarding mode guidance**: new mode selection step recommends TUN when no helper installed, saves choice to UserDefaults (b49a052)
- **Demo code removed**: deleted `AppRuntime.swift` (`AppMockTunnelRuntime`, `DemoConfigFactory`) from production source tree (05dd963)

## 📈 Documentation

- Updated `CLAUDE.md` known limitations: TUN uses mihomo gVisor not NetworkExtension; guard requires signed helper (d52bd23)
- `README.md`: TUN mode marked Stable, added unsigned build guidance (05dd963)
- Design spec and implementation plan committed to `docs/superpowers/` (fdd5cd1, 8977021)

## 📥 Assets

| Platform | File |
|----------|------|
| macOS Universal | Riptide-macos-universal.zip |
| macOS DMG | Riptide.dmg |
| Windows x64 | Riptide-windows-x64.msi |

## 🔐 Checksums

| File | SHA256 |
|------|--------|
| Riptide-macos-universal.zip | (populated by CI) |
| Riptide.dmg | (populated by CI) |
| Riptide-windows-x64.msi | (populated by CI) |

## 🚀 Installation

### macOS
1. Download the DMG or ZIP file
2. Open the DMG and drag Riptide to Applications, or extract the ZIP
3. On first launch, right-click and select 'Open' to bypass Gatekeeper (`xattr -cr` also works)
4. During onboarding, select **TUN mode** for full traffic interception without Apple signing

### Windows
1. Download the MSI installer
2. Run the installer and follow the prompts

## 📋 System Requirements

- **macOS**: macOS 14.0+ (Sonoma)
- **Windows**: Windows 10/11 64-bit
