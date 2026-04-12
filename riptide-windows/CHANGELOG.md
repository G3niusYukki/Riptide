# Riptide Windows Changelog

## [Unreleased]

### Added
- Windows proxy manager with mihomo integration
- System proxy configuration via WinHTTP API
- TUN mode support using wintun driver
- Full profile management (CRUD)
- Global hotkeys (Ctrl+Alt+P, Ctrl+Alt+M)
- System tray integration
- NSIS and MSI installer support
- WebView2 bootstrapper in installer
- Multi-language installer support (zh-CN, en-US)

### Changed
- Optimized Windows-specific UI styling for better font rendering
- Improved connection list grid layout for Windows displays
- Enhanced proxy card spacing and alignment

### Fixed
- UI alignment issues between macOS and Windows
- Font rendering on Windows (using Segoe UI font stack)
- Scrollbar styling consistency
- Input field focus states

### Known Issues
- TUN mode requires manual wintun.dll installation
- Hotkeys may conflict with other applications
- MSI installer requires elevated privileges for WebView2 installation

## [0.1.0] - 2026-04-12

### Added
- Initial Windows port of Riptide
- Core proxy functionality via mihomo
- System proxy toggle
- Basic profile management
- Connection monitoring
- Traffic statistics display
- Dark theme UI
