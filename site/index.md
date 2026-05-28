---
layout: home

hero:
  name: Riptide
  text: Cross-platform proxy client
  tagline: macOS · Windows · Linux — one profile format, one proxy core
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/riptide/riptide

features:
  - icon: 🚀
    title: Dual-engine architecture
    details: Pure-Swift proxy engine on macOS + mihomo sidecar. Native performance on every platform.
  - icon: 🔐
    title: MITM & Scripting
    details: HTTPS interception, request rewriting, and Surge-compatible JS scripting. Full control over your traffic.
  - icon: 📡
    title: 10 protocols, 8 transports
    details: Shadowsocks, VMess, VLESS, Trojan, Hysteria2, Snell, TUIC, WireGuard. QUIC, Reality, Multiplex.
  - icon: 🧠
    title: Clash-compatible rules
    details: DOMAIN, GEOIP, GEOSITE, RULE-SET, script rules. Drop in your existing Clash config and it works.
  - icon: 🌐
    title: Complete DNS stack
    details: DoH, DoT, DoQ, FakeIP, nameserver-policy. Industry-leading DNS pipeline.
  - icon: 🔄
    title: Subscription + WebDAV
    details: Auto-update subscriptions with quota tracking. WebDAV sync with conflict resolution.
---

## Quick Install

::: code-group
```bash [macOS]
brew install riptide
```

```bash [Windows]
winget install Riptide
```

```bash [Linux (coming soon)]
# Ubuntu 24.04+
sudo apt install riptide
```
:::
