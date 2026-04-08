# Riptide Windows Port - Implementation Plan

## Overview

This document outlines the complete implementation plan for porting Riptide to Windows 11, using Tauri 2.0 + Rust + React/TypeScript stack with mihomo as the proxy core.

## Technical Decisions (Confirmed)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Project Name | **Riptide** | Unified brand across platforms |
| Proxy Core | **mihomo** | Consistent with macOS version |
| Target OS | **Windows 11 only** | Modern APIs, reduced complexity |
| TUN Mode | **Windows Service** | Proper privilege elevation |
| MITM | **Basic MITM in v1** | Core feature parity |
| UI Style | **Riptide macOS dark theme** | Brand consistency |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Riptide Windows                       │
├─────────────────────────────────────────────────────────┤
│  Frontend (React + TypeScript)                          │
│  - Riptide dark theme UI                                │
│  - Profile/rules management                             │
│  - Connection logs & stats                              │
├─────────────────────────────────────────────────────────┤
│  Tauri 2.0 IPC Bridge                                   │
├─────────────────────────────────────────────────────────┤
│  Rust Backend                                           │
│  - mihomo sidecar lifecycle                             │
│  - sysproxy (system proxy control)                      │
│  - Config management                                    │
│  - Windows Service (TUN mode)                           │
├─────────────────────────────────────────────────────────┤
│  mihomo (sidecar binary)                                │
│  - Proxy protocols (SS, VMess, Trojan, etc.)           │
│  - TUN mode (via wintun.dll)                           │
│  - MITM/traffic inspection                             │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
riptide-windows/
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── src/
│   │   ├── main.rs
│   │   ├── lib.rs
│   │   ├── cmds/              # Tauri commands
│   │   │   ├── mod.rs
│   │   │   ├── proxy.rs       # Proxy control commands
│   │   │   ├── config.rs      # Config management
│   │   │   └── system.rs      # System proxy commands
│   │   ├── core/
│   │   │   ├── mod.rs
│   │   │   ├── mihomo.rs      # mihomo sidecar management
│   │   │   ├── service.rs     # Windows Service for TUN
│   │   │   └── sysproxy.rs    # System proxy wrapper
│   │   ├── config/
│   │   │   ├── mod.rs
│   │   │   ├── profiles.rs    # Profile management
│   │   │   └── rules.rs       # Rule management
│   │   └── utils/
│   │       ├── mod.rs
│   │       ├── dirs.rs        # App directories
│   │       └── logger.rs      # Logging setup
│   ├── resources/
│   │   ├── mihomo.exe         # Bundled mihomo binary
│   │   └── wintun.dll         # WireGuard TUN driver
│   └── icons/
├── src/                        # React frontend
│   ├── App.tsx
│   ├── main.tsx
│   ├── components/
│   │   ├── Layout/
│   │   ├── Sidebar/
│   │   ├── Proxies/
│   │   ├── Profiles/
│   │   ├── Rules/
│   │   ├── Connections/
│   │   └── Settings/
│   ├── hooks/
│   ├── services/              # Tauri IPC wrappers
│   ├── stores/                # State management
│   └── styles/                # Riptide dark theme
├── package.json
├── vite.config.ts
└── tsconfig.json
```

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

#### 1.1 Initialize Tauri Project
- Create new Tauri 2.0 project with React + TypeScript template
- Configure for Windows 11 target
- Set up development environment

#### 1.2 Rust Backend Scaffolding
- Set up module structure (cmds, core, config, utils)
- Add dependencies: sysproxy, tokio, serde, tauri
- Implement app directory management

#### 1.3 Frontend Skeleton
- Set up Vite + React + TypeScript
- Configure TailwindCSS for styling
- Create basic routing structure

#### 1.4 mihomo Integration
- Bundle mihomo.exe as sidecar
- Implement process lifecycle (start/stop/restart)
- Set up config file generation
- Health check and auto-restart

### Phase 2: Core Features (Week 3-4)

#### 2.1 Configuration Management
- Profile CRUD operations
- YAML config parsing/generation
- Import from URL/file
- Config validation

#### 2.2 System Proxy Control
- Integrate sysproxy crate
- Enable/disable system proxy
- PAC file support
- Proxy bypass rules

#### 2.3 Proxy UI
- Proxy group selector
- Latency testing
- Connection list view
- Traffic statistics

### Phase 3: Advanced Features (Week 5-6)

#### 3.1 Windows Service for TUN
- Create Windows Service project
- Implement service install/uninstall
- Handle privilege elevation
- Service status monitoring

#### 3.2 TUN Mode Integration
- Bundle wintun.dll
- Configure mihomo TUN settings
- Route table management
- DNS hijacking

#### 3.3 Basic MITM
- Certificate generation
- Trust store integration
- HTTPS inspection toggle
- Request/response logging

### Phase 4: Polish & Release (Week 7-8)

#### 4.1 UI Refinement
- Replicate Riptide macOS dark theme
- Animations and transitions
- System tray integration
- Notification support

#### 4.2 CI/CD Setup
- GitHub Actions workflow
- Code signing
- MSI/NSIS installer
- Auto-update mechanism

## Key Dependencies

### Rust (Cargo.toml)
```toml
[dependencies]
tauri = { version = "2", features = ["tray-icon", "protocol-asset"] }
tauri-plugin-shell = "2"
tauri-plugin-process = "2"
tauri-plugin-notification = "2"
tauri-plugin-autostart = "2"
sysproxy = "0.3"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
log = "0.4"
env_logger = "0.11"
anyhow = "1"
thiserror = "2"
windows-service = "0.7"
```

### Frontend (package.json)
```json
{
  "dependencies": {
    "@tauri-apps/api": "^2",
    "@tauri-apps/plugin-shell": "^2",
    "react": "^18",
    "react-dom": "^18",
    "react-router-dom": "^6",
    "zustand": "^4",
    "@tanstack/react-query": "^5",
    "tailwindcss": "^3",
    "framer-motion": "^11"
  }
}
```

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Windows Service complexity | Reference Clash Verge Rev implementation |
| TUN mode stability | Extensive testing, fallback to system proxy |
| MITM certificate trust | Clear user guidance, optional feature |
| mihomo compatibility | Pin to stable version, test thoroughly |

## Success Criteria

- [ ] mihomo starts/stops correctly
- [ ] System proxy enable/disable works
- [ ] Profile import/switch functional
- [ ] TUN mode with Windows Service works
- [ ] Basic MITM inspection works
- [ ] UI matches Riptide macOS dark theme
- [ ] Clean MSI installer with auto-update

## References

- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) - Architecture reference
- [mihomo](https://github.com/MetaCubeX/mihomo) - Proxy core
- [Tauri 2.0 Docs](https://v2.tauri.app/) - Framework documentation
- [wintun](https://www.wintun.net/) - TUN driver for Windows
