# Valheim Server Monitor

A native macOS menu bar app that installs and manages a Valheim dedicated server. Create a world, import a copy of a save, host in the background, and see server status without keeping a terminal open.

**Early preview.** Native installation, startup, and shutdown are being tested on Apple Silicon. The initial downloadable preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS may block first launch. A notarized release is the remaining distribution step before the intended low-friction experience. Do not treat the preview as a production-tested replacement for an existing server.

[Download preview releases](https://github.com/GlacianNex/valheim-server-monitor/releases) · [Setup and recovery](docs/SETUP.md) · [Development](CONTRIBUTING.md)

## Getting started

1. Download and unzip **Valheim-Server-Monitor.zip**. Open the app and let it copy itself into Applications (or drag it there in Finder).
2. Choose **Install Native Server**. The app downloads the server directly from Valve; no Steam account, running Steam client, Python, or CrossOver is required. On Apple Silicon, Valve's installer may need a one-time Rosetta installation, which the app asks you to approve. The server runs natively on Apple Silicon.
3. Choose **Create or Import a World**, set a server name and password, save, then select **Start Server** in the menu bar.

Crossplay is enabled by default, using Valheim's relay networking. The app displays the join code when the server reports one. Steam-only hosting requires forwarding the chosen UDP port and the next port on your router. The monitor cannot change your router configuration.

For an unnotarized preview, use macOS's per-app approval in **System Settings → Privacy & Security → Open Anyway** only if you trust this download. Do not disable Gatekeeper globally. Builds from source are also available.

## Included

- Automatic native server download and manual server updates, with installation progress and retry.
- Intel and Apple Silicon app binaries; macOS 13 or later.
- Saved profiles with separate world directories. Only one app-managed server runs at once.
- Copy-only imports of a one-world ZIP, modern world folder, or legacy `.db` with matching `.fwl`.
- World presets, modifiers, saving/backup settings, and admin/ban/allow lists, with underlined hover help.
- Status light, last reported player count, join-code copy, and logs.
- Graceful Save & Stop; the app does not force-kill a server after a save timeout.
- Separate settings for opening the monitor and starting the server at login.
- An idle-sleep assertion while hosting. Closing a laptop lid or logging out can still stop hosting.

## How it works

The app and background service are Swift executables built from this repository; there are no third-party Swift package dependencies. The runtime and worlds are separate from the app bundle:

```text
~/Library/Application Support/Valheim Server Monitor/
  profiles.json       # settings and passwords, mode 0600
  worlds/<profile>/   # a separate save directory for each profile
  runtime/           # SteamCMD and the native server downloaded from Valve
  logs/              # installation, server, and console logs
```

Server control uses an app-owned record containing the PID, executable path, and process start time. It does not stop servers by a broad process-name match. Development uses an explicit isolated `VSM_HOME`; login-item mutations are disabled there. Existing CrossOver installations, third-party servers, and their launch agents are not discovered, modified, or migrated.

## Current limits

- Login startup runs after a user signs in, not before login. Hosting ends on logout or shutdown.
- Player counts come from server logs and may be stale or unavailable. This is not a live player-query protocol or an in-game activity audit.
- Some world modifiers persist in saves. An unchecked flag does not remove a previously saved modifier. The profile editor explains this behavior.
- Imports check packaging and required files, not every world chunk's internal integrity. Import from a stopped source server or a consistent backup.
- No automatic migration, mod manager, remote server control, or CrossOver backend.
- The app asks before installing Rosetta. Installing it accepts Apple's license and may require macOS authorization.
- Updates are manual and require stopping the app-managed server. One previous server runtime is retained for recovery; world backups are handled by Valheim.

## Build

Install Xcode or its command-line tools, then:

```sh
swift test
scripts/build.sh
```

The universal app and ZIP are written to `dist/`. See [release instructions](docs/RELEASING.md) for Developer ID signing and notarization.

## License and attribution

The monitor code and its original server/mountain icon are MIT licensed. This is an unofficial community tool, not affiliated with Iron Gate, Coffee Stain, Valve, or Apple. Valheim and SteamCMD are downloaded from Valve and remain subject to their owners' terms; their binaries, game assets, and logos are not distributed in this repository or the app ZIP.

Server flags follow the [official Valheim dedicated-server guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/). The native launcher is inspected from Valve's dedicated-server app **896660**, macOS depot **896663**. See [verification notes](docs/VERIFICATION.md) for tested behavior and remaining checks.
