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

## Management package and native tests

The management companion needs .NET 8, source-built BepInEx and Valheim reference assemblies. Set `DOTNET` (if dotnet is not on PATH) and `GAME_MANAGED_PATH` to the downloaded native server's `Data/Managed` folder, then run `scripts/build-management.sh`. The script pins the loader, verifies Doorstop, and bundles attribution plus Doorstop's corresponding source. It never bundles game DLLs.

`swift test` covers schedules, time changes, restart sequencing, locks and package recovery. `scripts/test-status-update.sh` also opens and exercises the real AppKit windows using disposable storage.

For opt-in live tests, `scripts/test-managed-server.py` requires `VSM_TEST_BINARY`, `VSM_TEST_RUNTIME` (containing `valheim_server` and `steamapps`), `VSM_TEST_PACKAGE`, and `VSM_TEST_STEAMCMD`. It clones the supplied runtime, creates two unlisted test worlds on ports 29756–29757 and 29766–29767, verifies RCON and moderation, saves/restarts one world, and stops its test services. It never registers launch agents. Logs remain in the printed temporary directory.

For the real scheduled-restart window test, first set `VSM_TEST_UI_BUILD` to a disposable build directory and run `bash scripts/build-maintenance-smoke.sh`; then set `VSM_TEST_RESTART_HELPER` to that directory's `maintenance-window-smoke` executable when running the native test. The UI test uses a three-second deadline; the full 15/10/5/1-minute sequence is exercised using a deterministic clock in unit tests.
