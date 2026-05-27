# Changelog

## [2.1.0] — 2026-06-18

### Added

#### Daily Usability
- **Dashboard home page** — status cards (mode / node / speed), subscription quota bar with expiry countdown, recent connections list
- **Connection detail panel** — expandable inline detail with 5-tuple addressing, rule hit tracing, proxy chain visualization, traffic + timing stats
- **Subscription quota display** — parse `subscription-userinfo` HTTP header, show traffic bar + expiry countdown with 72h notification

#### DNS & Routing
- **Nameserver-policy DNS** — per-domain DNS resolver routing (e.g. `geosite:cn` → domestic DNS, default → DoH), supports Clash YAML `nameserver-policy` section
- DNSPipeline extended with `resolveNameserverPolicy()` for per-domain resolver selection

#### Configuration & Management
- **HTTP Rewrite engine** — URL regex-based reject / redirect / header-modify rules (Surge-compatible format), with CRUD UI in Settings
- **Config backup rotation** — 20-backup history in ConfigTabView, auto-backup on profile switch
- **Merge profile UX** — add merge sources, preview diffs, one-click apply (ConfigMergeView)

#### System Integration
- **One-click diagnostics** — 6 checks: helper installation, core binary availability, network connectivity, DNS resolution, proxy port listening, config integrity
- **Sparkle 2.9.2 auto-update** — Cmd+Shift+U menu item, UpdateSettingsView with channel selection
- **WiFi SSID auto-switch** — NetworkEnvironmentManager with CoreWLAN, auto-switches proxy mode + profile when joining different networks
- **Gateway mode backend** — GatewayEnabler: sysctl IP forwarding, pfctl NAT, bootpd DHCP configuration
- **Apple Shortcuts Intents** — SwitchProxyMode + SelectProfile discoverable in Shortcuts.app

#### MITM
- **MITM settings UI** — CA certificate download/install, host whitelist CRUD, exclude list, interception log
- HTTPRewriteEngine integrated with MITM pipeline

#### Surge JS Scripting
- **SurgeScriptBridge** — inject `$request`, `$response`, `$done`, `$persistentStore`, `$notification` into JavaScriptCore context for Surge-compatible script execution

#### Internationalization
- **10 languages** — en / zh-Hans / ja / ru / es + **new** ko / fa / pt-BR / vi + system auto-detect
- Language picker in Settings

#### UI / UX
- **Settings tab** — unified settings container with navigation to all sub-settings (Network, MITM, Rewrite, Updates, Core, Diagnostics, WebDAV, Language, Theme)
- **Theme switching** — System / Light / Dark with segmented picker; text colors use `Color.primary` for auto-adaptation; gradient background adapts to color scheme
- ConnectionListView: tap-to-expand rows with `ConnectionDetailView`

### Changed
- `ConnectionInfo` (MihomoAPIClient) extended with `rule`, `rulePayload`, `start`, `sourcePort`, `destinationPort` fields
- `ConnectionMetadata` extended with `sourcePort`, `destinationPort`
- `ModeCoordinator.getConnections()` now returns full `ConnectionInfo` structs instead of reduced tuples
- `ProxyMode` enum now conforms to `Codable`
- `SubscriptionUpdate` carries optional `SubscriptionUserinfo`
- `Subscription` model stores `SubscriptionUserinfo`

### Fixed
- SystemProxyControllerTests updated for new `ConnectionInfo.metadata.host` structure

---

## [2.0.0] — 2026-03

### Initial Release
- SwiftUI macOS app with 5 tabs (Config, Proxy, Traffic, Rules, Logs)
- Clash YAML config parsing + subscription management
- Protocol support: SS AEAD, VMess, VLESS, Trojan, Hysteria2, Snell, TUIC, SOCKS5, HTTP CONNECT, WireGuard (via sidecar)
- DNS: UDP, TCP, DoH, DoT, DoQ, FakeIP, Cache
- Rule engine: 15 rule types + GEOIP/GEOSITE/RULE-SET/SCRIPT
- Proxy groups: select, url-test, fallback, load-balance, relay
- TUN mode via mihomo sidecar
- mihomo + sing-box multi-core architecture
- WebDAV config sync
- Node editor + rule editor
- Menu bar extra with status + speed
- Global hotkeys
- Onboarding wizard
- 4 languages (en, zh-Hans, ja, ru)
