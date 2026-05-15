# Changelog

All notable changes to Riptide are documented here.

## [1.6.0] - TUN Mode UI Unlocked

- **TUN mode UI unlocked**: removed `tunUnavailable` warning block, added start/stop toggle button with keyboard shortcut (Return key) and visual state indicators (cf4b129)
- **TUN fallback guidance**: info message in UI explains sudo-based privilege escalation when helper is not installed (cf4b129)
- **SwiftLint compliance**: resolved trailing newline, vertical whitespace, and line length violations (e6f9dcb)

## [2.0.0] - GA Release

### 🎉 General Availability

Riptide exits Beta with a comprehensive GA push covering foundation hardening,
error unification, XPC maturation, test coverage, and visual editors.

### ✅ Foundation Hardening (P0)

- **Eliminated all force unwraps** — 4 unsafe `.first!` calls replaced with safe fallbacks
  in `MihomoPaths`, `MihomoDownloader`, `AppGroupStateStore`, `ProfileStore`
- **Eliminated all placeholder implementations** — `UDPSessionManager.process()` now forwards
  data through the proxy connection; `WebSocketExternalController.handlePutConfigs()` now
  parses and applies config changes
- **Removed self-import** — `TunnelProviderMessages.swift` no longer imports its own module

### 🔧 Error Handling Unification (P1)

- **New `RiptideError` unified error enum** — covers 17 subsystems with `LocalizedError`
  conformance, Chinese/English descriptions, and recovery suggestions
- **11 error enums with `LocalizedError`** — `TransportError`, `RuntimeError`,
  `CoreManagerError`, `MihomoAPIError`, `ClashConfigError`, `ProfileStoreError`,
  `SubscriptionError`, `SystemProxyError`, `VPNManagerError`, `AppGroupStateStoreError`,
  `NodeValidationError`

### 🔌 XPC Maturation (P1)

- **Automatic reconnection** — exponential backoff (3 attempts) on connection invalidation
  or interruption
- **Heartbeat monitoring** — 30-second periodic health checks with automatic reconnection
- **Timeout protection** — `verifyConnection()` and `fetchHelperVersion()` have 3-second
  timeouts to prevent hangs
- **Version check** — `getHelperVersion()` added to `HelperToolProtocol`; version is fetched
  and stored on connection establishment
- **New error cases** — `ConnectionError.versionMismatch` and `.timedOut`
- **XPC tests** — `HelperToolConnectionTests` covering error types and RiptideError wrapping

### 🧪 Test Coverage (P2)

- **71 new tests** across 5 test suites:
  - `HelperToolConnectionTests` (4) — XPC error types
  - `TUNRoutingEngineTests` (26) — VPN errors, config, PacketHandler, TCP/UDP parsing
  - `UserSpaceTCPTests` (18) — TCP state machine, connection IDs, handshake lifecycle
  - `WebDAVClientTests` (6) — WebDAV error types, file model
  - `ConfigMergerTests` (17) — merge logic, proxy/rule/DNS/group merging

### 🎨 Visual Editors (P2)

- **Node Editor fixes** — `parseProxiesFromYAML` now uses `ClashConfigParser`;
  `generateYAMLWithNode`, `generateUpdatedYAML`, `generateYAMLWithoutNode` now use Yams
  for proper YAML manipulation
- **Rule Editor** (new) — `RuleEditorView` with drag-to-reorder, add/delete rules,
  10 supported rule types, policy picker from available proxies/groups
- **Config Merge UI** (new) — `ConfigMergeView` for managing merge sources (file/manual),
  previewing diffs (added/modified/removed proxies + rule changes), and one-click apply
- **Config Import Preview** (new) — `ConfigImportPreviewView` shows proxy/rule/group counts
  and details before importing; integrated into ConfigTabView's import flow
- **Rule Set Auto-Update** (new) — `RuleSetProvider` lifecycle integrated into `AppViewModel`;
  providers start/stop with profile activation; UI section shows sources with manual refresh

### 📦 Infrastructure

- Added `Yams` dependency to `RiptideApp` target for YAML manipulation
- `Swift 6 concurrency` — ~12 compiler warnings fixed in RiptideApp (NodeEditorViewModel,
  AppViewModel, ConfigDropDelegate, ConfigMerger, SystemProxyGuard, SystemProxyController,
  ModeCoordinator)

### 📋 Known Limitations

- VPN/TUN tests require NetworkExtension (not available in test environment)
- Swift 6 strict concurrency warnings remain in some actor-isolated views
- Deprecated API warnings in `SMJobBlessManager` and `StatusBarController` (fallback paths)
- MITM framework is scaffolded but not production-ready

---

## [1.3.0] - Previous Beta

- mihomo TUN integration with gVisor stack
- SMAppService migration (macOS 13+)
- First-run onboarding wizard
- Atomic mode switching with 500ms cooldown
- TUN auto-recovery with 10-second health monitoring
- System proxy guard with 5-second violation detection
- Subscription auto-update (5-minute interval)
- WebDAV config sync
- 4-language localization (en, zh-Hans, ja, ru)
- Menu bar extra with traffic monitoring
- 491 tests in 76 suites
