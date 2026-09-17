# Changelog

## 1.1.6 — 2026-09-17

- Check for manager updates every six hours. The top menu line stays grey when up to date and offers a one-click verified download and installation when an update is available.
- Keep the Valheim server build line informational and greyed out.
- Show Normal modifier values for fresh worlds and clarify preset inheritance, per-option help, passwords, and numeric settings.

## 1.1.5 — 2026-09-17

- Correct Valheim spelling in the app, repository links, and new download filenames. Existing app locations and data remain supported.
- Use a copper V app icon. Keep the status light, player count, and yellow update indicator together in one menu-bar item.
- Show one server update action with the matching yellow indicator; remove duplicate update entries.

## 1.1.4 — 2026-09-16

- Keep the latest player count reported in logs, including every valid disconnect count, across refreshes and manager relaunches.
- Verify each required runtime architecture separately to support macOS 27 lipo while retaining Intel and Apple Silicon validation.
- Preserve server readiness and join codes as logs grow, and reconstruct status when the manager reopens.

## 1.1.2 — 2026-09-14

- The top bar shows Stopping… during shutdown, including when another server remains online.
- Player counts follow log announcements and connection snapshots in order.
- Optional case-sensitive world seed when creating a fresh server; blank keeps random generation.
- Existing and imported world seeds are shown read-only. Changing server settings never rewrites the world's seed.

## 1.0.0 — 2026-09-14

First stable release of Valheim Server Manager for Mac.

- Native macOS hosting with anonymous Valve installation, Apple Silicon and Intel app binaries, and Developer ID signing with Apple notarization.
- Multiple simultaneous servers with independent status, logs, ports, settings, and login startup.
- Per-server submenus for Start/Save & Stop, join code, settings, logs, and confirmed deletion with recoverable saves.
- Read-only settings while hosting and automatic display of inherited settings from imported world metadata.
- Explicit List my server checkbox and optional empty passwords for unlisted servers.
- App replacement now detects actual process exit and restores running/auto-start servers after success.
- Shared Valheim Server Build checks and confirmed runtime updates that save, stop, and restore affected servers.
- Copy-only world imports, automatic world filenames and port defaults, and a backup when migrating older profile databases.

Historical preview downloads and notes remain in [GitHub Releases](https://github.com/GlacianNex/valheim-mac-server/releases).
