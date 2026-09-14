# Contributing

Use macOS 13+ and a current Swift toolchain (Swift 5.9 or later). No downloaded game files are needed for unit tests.

```sh
swift test
swift build
VSM_HOME="$PWD/.build/manual-test" .build/debug/ValheimServerMonitor
```

Always set `VSM_HOME` for development. Login-item registration is deliberately disabled with this override. Use disposable profiles and a port pair different from any existing server. Never use a real world for a lifecycle test.

Architecture:

- `Sources/ServerCore`: profiles and schema migration, saved-world settings, copy-only imports, shared Valve runtime, independent process lifecycle, and launchd integration.
- `Sources/ValheimServerMonitor`: AppKit setup, profile editor, menu, and CLI/service entry points.
- `Tests/ServerCoreTests`: preservation, argument validation, imports, locks, process ownership, and log parsing.
- `scripts/build.sh`: universal macOS app packaging with an original generated icon.

Pull requests should explain the concrete behavior change and its verification. Avoid committing runtime binaries, world saves, logs, profile databases, credentials, or signing material. Changes to shutdown, import, and process ownership require focused regression tests. Keep the app native-only and dependency-light.

For real-server testing, see `scripts/integration.py`. It requires Python only as a developer test harness; the distributed app does not use Python. The harness requires an explicit isolated root and installs a disposable profile using an already-downloaded runtime. It never registers launch agents.
