# Development

```
RiptideApp
  AppViewModel
    ModeCoordinator
      MihomoRuntimeManager
        riptide-mihomo-service   TUN, root, Unix socket
        RiptideHelper            system proxy, XPC
```

System proxy and TUN share one state machine: `ModeCoordinator`. TUN does not fall back to sing-box or to `sudo networksetup`.

```bash
swift test
swiftlint lint --strict Sources/Riptide Sources/RiptideApp
```

Library code goes in `Sources/Riptide/`. See `AGENTS.md`.
