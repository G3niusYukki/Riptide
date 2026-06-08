# Getting Started

## System Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| Windows | 10 build 1809+ | WebView2 is required; Win 7 is not supported |
| WebView2 Runtime | Shipped with Win 11 | Auto-installed via bootstrapper on Win 10 (configured in `tauri.conf.json`) |
| Disk space | ~150 MB | mihomo binary, geo assets, profiles, logs |

## Download & Install

Grab the latest release from [GitHub Releases](https://github.com/riptide/riptide/releases).

Two installer formats are available:

| Format | Filename | Use case |
|---|---|---|
| **MSI** | `Riptide_<version>_x64_en-US.msi` | Enterprise / managed deployment; supports silent install (`msiexec /i Riptide.msi /qn`) |
| **NSIS** | `Riptide_<version>_x64-setup.exe` | Per-user install; recommended for most users |

Run the installer and follow the prompts. Riptide installs to `%LOCALAPPDATA%\Riptide` (NSIS) or `C:\Program Files\Riptide` (MSI).

## First Launch

1. **Open Riptide** — a system tray icon appears in the notification area.
2. **Choose a proxy mode** from the tray menu or the main UI:
   - **System Proxy** — configures the Windows system proxy (HTTP/SOCKS). No elevation needed.
   - **TUN** — routes all traffic through a virtual interface. Requires one-time service install (see below).
   - **Off** — disables proxying.

## Import a Profile

Riptide manages Clash-compatible YAML profiles. There are three ways to import:

### From a subscription URL

1. Go to **Profiles** in the sidebar.
2. Click **Add Subscription**.
3. Paste your subscription URL.
4. Set an auto-update interval (default: 24 hours, recommended: 6 hours).
5. Click **Import**.

### From a file

Drag and drop a `.yaml` or `.yml` file onto the Profiles page, or use **Import from File**.

### From a share URI

Paste a `ss://`, `vmess://`, `vless://`, `trojan://`, `hysteria2://`, or `tuic://` URI directly into the profile editor. Riptide auto-detects the protocol and creates a proxy entry.

You can also use the deep link: `riptide://import?url=...` or `riptide://import?uri=...`.

## TUN Mode Setup

TUN mode routes all system traffic through a virtual network interface powered by mihomo's gVisor stack (no custom driver needed). It requires a one-time elevated service install:

1. Click **Install TUN Service** in Settings → Network (or onboarding prompt).
2. A UAC dialog appears — approve it. This registers `riptide-tun-service.exe` as a Windows service (`RiptideTUN`) running as `SYSTEM`.
3. After installation, TUN mode activates without further UAC prompts.

The service reads its configuration from `%PROGRAMDATA%\Riptide\service.conf`.

::: tip
The `wintun.dll` driver ships next to both `riptide.exe` and `mihomo.exe`. The installer copies it automatically — no manual download needed.
:::

## Configuration Directories

```
%APPDATA%\Riptide\                    # user-scope state
├── profiles\                         # profile YAML + metadata sidecars
├── active.json                       # selected profile id
├── dns_policy.json                   # DNS overrides
├── region_preset.json                # region preset config
├── tls_tricks.json                   # TLS fingerprint settings
├── kill_switch.json                  # kill switch state
├── webdav_config.json                # DPAPI-encrypted WebDAV credentials
├── mihomo\
│   ├── mihomo.exe                    # proxy core binary
│   └── config.yaml                   # generated — do not edit
├── logs\
│   └── riptide.log.<date>            # daily rolling logs
└── geoip.metadb / geosite.dat        # geo databases

%PROGRAMDATA%\Riptide\                # machine-scope (SYSTEM-readable)
└── service.conf                      # TUN service launch params
```
