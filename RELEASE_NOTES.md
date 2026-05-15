# Riptide v1.6.0 — TUN Mode UI Unlocked

**Release Date:** 2026-05-15

## ✨ Highlights

TUN mode UI is now fully unlocked. The start/stop controls are available directly in the config view — no more "not yet available" warning.

## ✨ New Features

- **TUN mode UI unlocked**: removed `tunUnavailable` warning block, added start/stop toggle button with keyboard shortcut (Return key) and visual state indicators (cf4b129)
- **TUN fallback guidance**: info message in UI explains that sudo will be used for privilege escalation when helper tool is not installed (cf4b129)

## 🐛 Fixes

- **SwiftLint compliance**: resolved trailing newline, vertical whitespace, and line length violations (e6f9dcb)

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
