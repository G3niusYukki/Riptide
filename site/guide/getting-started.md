# Getting Started

## Installation

### macOS

```bash
brew install riptide
```

Or download the latest `Riptide.dmg` from
[GitHub Releases](https://github.com/riptide/riptide/releases).

Requirements: macOS 14+ (Sonoma or later).

### Windows

```bash
winget install Riptide
```

Or download `Riptide.msi` / `RiptideSetup.exe` from
[GitHub Releases](https://github.com/riptide/riptide/releases).

Requirements: Windows 10+ with WebView2.

### Linux

Support coming in Riptide v3.0. Target: Ubuntu 24.04+.

## First Launch

1. **Open Riptide** — a menu bar icon (macOS) or system tray icon (Windows) appears.
2. **Add a profile** — paste a Clash-compatible subscription URL or import a YAML config file.
3. **Select a proxy** — pick a node from the proxy group.
4. **Turn on** — switch to System Proxy or TUN mode.

## Quick Tour

| Feature | Where |
|---|---|
| Dashboard | Home tab — speed, connections, subscriptions |
| Proxies | Proxies tab — node list, groups, latency |
| Profiles | Profiles tab — manage/switch config profiles |
| Rules | Rules tab — view/edit routing rules |
| Logs | Logs tab — real-time connection log |
| Settings | Settings → proxy mode, MITM, DNS, sync |

## Importing a Subscription

1. Go to **Profiles → Subscriptions**.
2. Click **Add Subscription**.
3. Paste your subscription URL.
4. Set auto-update interval (recommended: 6 hours).
5. Click **Import**.

Riptide parses Clash-compatible subscription formats — Base64-encoded proxy lists, SIP008, and Clash YAML.
