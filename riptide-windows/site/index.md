---
layout: home

hero:
  name: Riptide Windows
  text: Native Windows proxy client
  tagline: Tauri 2 + React + mihomo — TUN, system proxy, kill switch, WebDAV sync
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: Platform Details
      link: /platform/windows

features:
  - icon: 🖥️
    title: Native Windows app
    details: Built on Tauri 2 with a React/TypeScript frontend and Rust backend. Ships as MSI and NSIS installers.
  - icon: 🛡️
    title: TUN via SCM service
    details: riptide-tun-service.exe runs mihomo as SYSTEM for unprivileged TUN. One-time UAC, then silent.
  - icon: 🔒
    title: Kill switch
    details: Route-table blackhole on TUN crash prevents accidental traffic leaks. Opt-in, manual release via UI.
  - icon: 🔄
    title: Recovery watchdog
    details: Detects sleep/wake and network changes. Health-probes mihomo and auto-restarts after consecutive failures.
  - icon: 📡
    title: 6 protocols
    details: Shadowsocks, VMess, VLESS, Trojan, Hysteria2, TUIC — all managed through Clash-compatible YAML profiles.
  - icon: ☁️
    title: WebDAV sync
    details: HTTPS-only backup of profiles, DNS policy, and sidecars. DPAPI-encrypted credential storage.
---

## Quick Install

Download the latest installer from [GitHub Releases](https://github.com/riptide/riptide/releases):

- **MSI** — `Riptide_<version>_x64_en-US.msi` (enterprise-friendly, silent install)
- **NSIS** — `Riptide_<version>_x64-setup.exe` (per-user install, auto-updater path)

Requires Windows 10 1809+ with WebView2 (auto-installed on Win 10; ships with Win 11).
