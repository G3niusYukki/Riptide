# Contributing

Riptide is a macOS 14+ app. Pull requests for other platforms will be closed.

1. Branch from `master`.
2. Keep the change in `Sources/Riptide/` when both the app and the CLI need it.
3. Add or update a test for behavior changes.
4. Run `swift test --filter` for the area you touched, then `swiftlint lint --strict` on the Swift files you edited.
5. Update `CHANGELOG.md` under the current version when the change is user-visible.
6. Do not commit signing material.

See `AGENTS.md` for the layout and the TUN rule.
