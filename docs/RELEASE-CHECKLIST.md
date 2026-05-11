# Riptide GA Release Validation Checklist

Execute this checklist before tagging a GA release. All items must pass.

---

## Build & Tests

- [ ] `swift build` — zero warnings in changed files
- [ ] `swift test` — all tests pass (≥562 tests)
- [ ] SwiftLint — zero violations

## XPC Helper

- [ ] Helper installs via SMAppService (macOS 13+)
- [ ] Helper installs via SMJobBless fallback (macOS 12)
- [ ] Helper version check works (old helper triggers update prompt)
- [ ] Helper survives app restart
- [ ] Helper reconnection works after XPC interruption

## System Proxy Mode

- [ ] System proxy enables correctly (HTTP + SOCKS5)
- [ ] Browser traffic routes through proxy
- [ ] System proxy disables cleanly
- [ ] System proxy guard detects external modification and restores
- [ ] System proxy guard 5-second check cycle works

## TUN Mode

- [ ] TUN interface creates successfully
- [ ] DNS resolution works through TUN
- [ ] TCP traffic routes through TUN
- [ ] TUN health monitor (10s interval) detects failures
- [ ] TUN auto-recovery restarts mihomo on failure
- [ ] TUN route exclusions for LAN work (192.168.x.x, 10.x.x.x)

## Config Management

- [ ] Import YAML config via file picker
- [ ] Import preview shows correct proxy/rule/group counts
- [ ] Import preview confirms before applying
- [ ] Drag-and-drop config import works
- [ ] Subscription URL import works
- [ ] Config export saves valid YAML

## Visual Editors

- [ ] Node editor loads existing proxies from config
- [ ] Node editor adds new proxy (SS/VMess/VLESS/Trojan)
- [ ] Node editor edits existing proxy
- [ ] Node editor deletes proxy
- [ ] Node editor duplicates proxy
- [ ] Node editor validates fields (required fields, port range)
- [ ] Rule editor loads existing rules
- [ ] Rule editor adds new rule (DOMAIN/SUFFIX/IP-CIDR/GEOIP/MATCH)
- [ ] Rule editor deletes rule
- [ ] Rule editor reorders rules via drag
- [ ] Config merge adds file source
- [ ] Config merge previews diff correctly
- [ ] Config merge applies merge

## Config Backup

- [ ] Automatic backup on profile switch
- [ ] Manual backup creates backup file
- [ ] Backup list shows all backups with timestamps
- [ ] Restore from backup creates new profile
- [ ] Delete backup removes file
- [ ] Old backups pruned (max 20)

## Rule Set Auto-Update

- [ ] Rule set providers start on profile activation
- [ ] Rule set providers stop on profile deactivation
- [ ] Manual refresh works
- [ ] Rule set status displays correctly in UI

## Proxy Groups & Health Check

- [ ] url-test group auto-selects lowest latency
- [ ] fallback group switches on failure
- [ ] load-balance distributes connections
- [ ] Latency test shows correct values with color coding
- [ ] Manual latency test button works

## Subscriptions

- [ ] Add subscription URL
- [ ] Auto-update scheduler runs (5-minute interval)
- [ ] Manual update triggers refresh
- [ ] Subscription error displays correctly
- [ ] Delete subscription removes it

## UI & Localization

- [ ] All 4 languages display correctly (en, zh-Hans, ja, ru)
- [ ] Language switch works without restart
- [ ] Theme switch (System/Light/Dark) works
- [ ] Menu bar icon and traffic display work
- [ ] Global hotkeys work
- [ ] Onboarding wizard displays on first run

## WebDAV Sync

- [ ] WebDAV connection test succeeds
- [ ] Push config to WebDAV
- [ ] Pull config from WebDAV
- [ ] Conflict resolution works

## Performance & Stability

- [ ] App starts in <2 seconds
- [ ] Memory usage stable after 30 minutes
- [ ] 100 concurrent connections handled
- [ ] DNS cache functions correctly
- [ ] Log viewer doesn't lag with 1000+ entries

## Installation

- [ ] DMG opens and installs correctly
- [ ] App launches after DMG install
- [ ] First-run onboarding displays
- [ ] Helper installs via onboarding wizard
- [ ] Uninstall removes app cleanly
