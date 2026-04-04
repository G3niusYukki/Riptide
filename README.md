# Riptide

Riptide is a macOS proxy client built with Swift 6, integrating the [mihomo](https://github.com/MetaCubeX/mihomo) core to provide production-grade proxy and TUN mode support.

**Current state: Beta** — Full mihomo integration complete with System Proxy mode, TUN mode (via privileged helper), profile management, subscription workflow, and menu bar UI.

---

## Features

### Core Proxy Support (via mihomo)

| Protocol | Status |
|----------|--------|
| HTTP/SOCKS5 | ✅ Supported |
| Shadowsocks (AEAD) | ✅ Supported |
| VMess | ✅ Supported |
| VLESS (XTLS/Vision) | ✅ Supported |
| Trojan | ✅ Supported |
| Hysteria2 | ✅ Supported |

### Runtime Modes

- **System Proxy Mode** — Configures macOS system proxy settings, routes traffic through mihomo's HTTP/SOCKS5 ports
- **TUN Mode** — Uses mihomo's gVisor-based TUN stack to intercept all system traffic (requires privileged helper)

### Configuration

- **Clash-compatible YAML parser** with strict validation
- **Rule engine**: `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`, `IP-CIDR6`, `GEOIP`, `PROCESS-NAME`, `MATCH/FINAL`, `RULE-SET`
- **Proxy groups**: `select`, `url-test`, `fallback`, `load-balance`
- **DNS policy**: DoH, DoT, DoQ, fake-IP, nameserver fallback

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Riptide SwiftUI App                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
│  │ Config Tab  │  │ Proxy Tab   │  │ System Proxy/TUN   │   │
│  │             │  │             │  │ Mode Selector       │   │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘   │
│         └─────────────────┴────────────────────┘             │
│                           │                                 │
│              ┌────────────▼────────────┐                    │
│              │   MihomoRuntimeManager  │                    │
│              │   (Config Gen + XPC + API)                  │
│              └────────────┬────────────┘                    │
└───────────────────────────┼─────────────────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │    RiptideHelper (root)   │  ← SMJobBless
              │  launch/terminate mihomo  │
              └─────────────┬─────────────┘
                            │
              ┌─────────────▼─────────────┐
              │        mihomo (root)      │
              │   ┌─────────────────┐    │
              │   │ TUN Device      │    │  ← gVisor stack
              │   │ Proxy Protocols │    │  ← VLESS/VMess/SS/etc
              │   │ REST API :9090  │◄───┘
              │   └─────────────────┘
              └─────────────────────────────┘
```

---

## Requirements

- macOS 14+
- Swift 6.2+
- Xcode 16+ with Swift Package Manager
- Apple Developer account (for signing the privileged helper tool)

---

## Quick Start

### 1. Clone and Build

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
swift build
```

### 2. Download mihomo Binary

```bash
./Scripts/download-mihomo.sh
```

This downloads the mihomo core binary (universal binary for Intel + Apple Silicon).

### 3. Run Tests

```bash
swift test
```

All 233 tests should pass.

### 4. Build Helper Tool (for TUN mode)

The privileged helper tool requires proper code signing:

1. Open `RiptideHelper/Resources/Info.plist`
2. Replace `YOUR_TEAM_ID` with your Apple Developer Team ID
3. Build and sign the helper:

```bash
cd RiptideHelper
swift build
codesign --sign "Developer ID Application: Your Name" --entitlements Entitlements.plist .build/debug/RiptideHelper
```

### 5. Run the App

**Via Xcode (recommended):**
- Open the project in Xcode
- Select `RiptideApp` scheme
- Click Run

**Via command line:**
```bash
swift run RiptideApp
```

---

## Example Configuration

Create a `config.yaml`:

```yaml
mode: rule
mixed-port: 6152
external-controller: 127.0.0.1:9090

proxies:
  - name: "hk-node"
    type: vless
    server: "example.com"
    port: 443
    uuid: "550e8400-e29b-41d4-a716-446655440000"
    flow: xtls-rprx-vision
    servername: example.com

  - name: "sg-ss"
    type: ss
    server: "sg.example.com"
    port: 8388
    cipher: aes-256-gcm
    password: "your-password"

proxy-groups:
  - name: "auto-select"
    type: url-test
    proxies:
      - hk-node
      - sg-ss
    url: http://www.gstatic.com/generate_204
    interval: 300

rules:
  - DOMAIN-SUFFIX,google.com,auto-select
  - DOMAIN-KEYWORD,ads,REJECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,auto-select
```

---

## Usage

### System Proxy Mode

1. Import your configuration file
2. Select "System Proxy" mode
3. Click "Start"
4. The app will configure macOS system proxy settings automatically

### TUN Mode

1. First time only: Install the privileged helper tool
   - Click "Install Helper Tool" button
   - Enter your macOS administrator password
2. Select "TUN" mode
3. Click "Start"
4. All system traffic is routed through the TUN interface

### Switching Proxies

In the Proxy tab, click any node to switch active proxy. For proxy groups, the best node is auto-selected based on latency (url-test mode).

---

## Project Structure

```
Sources/
  Riptide/
    Mihomo/           # mihomo integration layer
      MihomoPaths.swift
      MihomoConfigGenerator.swift
      MihomoAPIClient.swift
      MihomoRuntimeManager.swift
    XPC/              # Privileged helper communication
      HelperToolProtocol.swift
      HelperToolConnection.swift
    AppShell/         # Import workflow, profile store
    Config/           # Clash YAML parser
    Models/           # Core data models
    Rules/            # Rule engine
  RiptideHelper/      # Privileged helper tool (separate package)
    Sources/
      main.swift
      HelperTool.swift
      MihomoLauncher.swift
  RiptideApp/         # SwiftUI app entrypoint
    SMJobBlessManager.swift
    Views/
      HelperSetupView.swift
      ConfigTabView.swift
Resources/
  mihomo              # Downloaded mihomo binary
Scripts/
  download-mihomo.sh  # Download script
```

---

## How It Works

### 1. Configuration Generation

When you start a profile:

1. `MihomoConfigGenerator` transforms `RiptideConfig` to mihomo-compatible YAML
2. YAML is written to `~/Library/Application Support/Riptide/mihomo/config.yaml`
3. Previous config is backed up to `config.yaml.bak`

### 2. Helper Tool & XPC

For TUN mode (requires root):

1. `SMJobBlessManager` installs `RiptideHelper` to `/Library/PrivilegedHelperTools/`
2. `HelperToolConnection` establishes XPC connection to the helper
3. Helper launches mihomo with root privileges
4. mihomo creates the TUN device

### 3. Runtime Control

Once running:

1. `MihomoAPIClient` connects to mihomo's REST API (port 9090)
2. Live traffic stats, connection list, proxy switching via API
3. Health checks ensure mihomo is responsive

### 4. Mode Coordination

- **System Proxy Mode**: `ModeCoordinator` sets macOS system proxy to `127.0.0.1:6152`
- **TUN Mode**: mihomo manages routes and DNS directly

---

## Security Considerations

1. **Privileged Helper**: RiptideHelper runs as root via SMJobBless. It only:
   - Launches mihomo from `/Library/Application Support/Riptide/mihomo`
   - Accepts config paths under `~/Library/Application Support/Riptide/mihomo/`
   - Terminates mihomo process

2. **Config Path Validation**: The helper validates all paths are within allowed directories before use

3. **Code Signing**: Both the main app and helper must be signed with the same Team ID

---

## Roadmap

### Current (Beta)
- ✅ mihomo core integration
- ✅ System Proxy mode
- ✅ TUN mode with privileged helper
- ✅ SwiftUI app with menu bar
- ✅ Proxy switching and latency tests

### Future
- GeoIP database auto-update
- Rule-set provider auto-update
- Advanced traffic statistics dashboard
- Script/Merge configuration support
- Web-based external controller UI

---

## Contributing

Contributions are welcome.

- Keep changes modular and test-backed
- All code must pass Swift 6 strict concurrency checks
- Add tests for new functionality
- Update documentation for user-facing changes

---

## License

MIT License - See LICENSE file

---

## Acknowledgments

- [mihomo](https://github.com/MetaCubeX/mihomo) - The proxy core powering Riptide
- [Clash](https://github.com/Dreamacro/clash) - Original configuration format
