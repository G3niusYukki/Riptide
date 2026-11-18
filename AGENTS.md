# AGENTS.md

macOS 14+ only. Do not add Windows, Linux, or iOS targets, jobs, or docs.

## Shape

Shared logic belongs in `Sources/Riptide/`. The app and the `riptide` CLI both use that library. `Sources/Riptide/Riptide.swift` is the module entry; do not put logic there.

TUN has one owner: `Sources/Riptide/Mihomo/ServiceMode/`. `ModeCoordinator` is the mode state machine. Do not put sing-box checks or `sudo networksetup` back on the TUN or system-proxy start path.

## Rules

- Swift 6: actors or `@MainActor` for shared mutable state. Value types are `Equatable`, `Sendable`, `Codable`.
- No force unwraps in production code.
- Errors are `LocalizedError` enums. Fail visibly. The logbook may use `try?` because diagnostics must not block the proxy path.
- Inject dependencies. The usual pattern is `Module.setFoo(...) async` from `AppViewModel.init`.
- SwiftLint strict: identifier length at least 2, cyclomatic complexity warning 18 / error 25.
- Do not commit certificates, private keys, `.p12`, `.cer`, or a personal certificate CN. The public team ID `39Q4M52XNQ` and the helper requirement string are allowed.
- Do not describe a scaffolded feature as shipped. If README and the code disagree, trust the code and fix the doc.

## Checks

```bash
swift test --filter "SuiteName"
swiftlint lint --strict path/to/File.swift
swift test
```

UI tests live in `Tests/RiptideAppUITests/` and need a GUI. A headless `swift test` of that target can abort; that is an environment limit, not a product failure.

After a release bundle, launch `.build/release-dmg/RiptideApp.app`. `swift run` does not load Sparkle the way the bundle does.

## Design notes that are still current

- `docs/decisions/0004-helper-trust-model.md`
- `docs/decisions/2026-06-02-d3-service-mode.md`
- `docs/decisions/0012-macos-only-direction-and-signing-identity.md`
- `docs/signing-setup.md`
