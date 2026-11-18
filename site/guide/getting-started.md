# Getting started

Riptide runs on macOS 14 or later.

## Install

Download `Riptide.dmg` from GitHub Releases, or build it:

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
swift run RiptideApp
```

A packaged app:

```bash
./Scripts/build-release.sh
open .build/release-dmg/RiptideApp.app
```

## First launch

1. Import a Clash subscription or a YAML config.
2. Pick a node.
3. Choose System Proxy or TUN, then connect.

The first TUN start installs `riptide-mihomo-service` and asks for an administrator password once. Later toggles do not.
