# Changelog

## 1.1.2 — 2026-09-14

- The top bar shows Stopping… during shutdown, including when another server remains online.
- Player counts use later connection snapshots and show unknown after a lost connection instead of treating retained reconnect sockets as connected players.
- Optional case-sensitive world seed when creating a fresh server; blank keeps random generation.
- Existing and imported world seeds are shown read-only. Changing server settings never rewrites the world's seed.

## 1.0.0 — 2026-09-14

First stable release of Valhiem Server Manager for Mac.

- Native macOS hosting with anonymous Valve installation, Apple Silicon and Intel app binaries, and Developer ID signing with Apple notarization.
- Multiple simultaneous servers with independent status, logs, ports, settings, and login startup.
- Per-server submenus for Start/Save & Stop, join code, settings, logs, and confirmed deletion with recoverable saves.
- Read-only settings while hosting and automatic display of inherited settings from imported world metadata.
- Explicit List my server checkbox and optional empty passwords for unlisted servers.
- App replacement now detects actual process exit and restores running/auto-start servers after success.
- Shared Valheim Server Build checks and confirmed runtime updates that save, stop, and restore affected servers.
- Copy-only world imports, automatic world filenames and port defaults, and a backup when migrating older profile databases.

Historical preview downloads and notes remain in [GitHub Releases](https://github.com/GlacianNex/valhiem-mac-server/releases).
