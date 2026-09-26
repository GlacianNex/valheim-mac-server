# Valheim Server Manager for Mac

Host a Valheim dedicated server on your Mac. This native macOS menu bar app installs the server, creates or imports worlds, and manages hosting in the background without keeping a terminal open.

**Requires macOS 13 Ventura or later.** The download includes Apple Silicon and Intel Mac binaries. Runtime testing is currently on Apple Silicon; Intel hardware validation is still pending. Allow at least 6 GB for setup, plus space for each server’s managed runtime and its rollback copy. APFS clones reduce physical disk use when available. The hosting app is for macOS only.

**Version 1.2.4** adds automatic management-tool setup for existing servers, scheduled restarts, player messaging and moderation, and one-hour performance graphs. [Full release notes](docs/releases/1.2.4.md).

[Download for Mac](https://github.com/GlacianNex/valheim-mac-server/releases/latest) · [Mac setup and recovery](docs/SETUP.md) · [Development](CONTRIBUTING.md)

<img src="docs/images/server-manager-menu-1.1.5.png" alt="Illustrated preview of the Valheim Server Manager for Mac 1.1.5 menu with a server update available" width="680">

*Illustrated preview of version 1.1.5 with a server update available.*

## Getting started on your Mac

1. Download and unzip **Valheim-Server-Manager-for-Mac.zip**. Open the app and let it copy itself into Applications (or drag it there in Finder).
2. Choose **Install Native Server**. The app downloads the server directly from Valve; no Steam account, running Steam client, Python, or CrossOver is required. On Apple Silicon, Valve's installer may need a one-time Rosetta installation, which the app asks you to approve. The server runs natively on Apple Silicon.
3. Choose **New Server…**, set a server name, choose whether to **List my server**, and save. Listed servers require a password; unlisted servers can use an empty password. Hover over that server in the menu bar to start it or view its settings.

Crossplay is enabled by default, using Valheim's relay networking. The app displays the join code when the server reports one. Steam-only hosting requires forwarding the chosen UDP port and the next port on your router. The manager cannot change your router configuration.

macOS may show its normal first-open confirmation for an app downloaded from the internet.

Choose an optional **World seed** when creating a new server, or leave it blank for random generation. Existing and imported worlds show their saved seed read-only in settings.

## Included

- Automatic native server download and optional automatic server updates, with installation progress and retry.
- An available server update adds a yellow **!** badge to the menu bar and an **Update Valheim Server…** action at the top of the menu. Servers keep running until you approve the update, unless you enable automatic server updates.
- The menu shows the installed server's Steam build and checks Valve's stable release on launch and every 10 minutes while hosting continues. Click an available update to save, stop, update, and restart the servers that were running.
- **Automatically Update All Valheim Servers** is off by default. When enabled, a new stable build starts a 15-minute warning countdown, then triggers save → stop → update → restart. The countdown can be cancelled. Servers without working management support must report zero players; unknown counts block their updates. The manager must be open. Managed servers receive chat and center-screen warnings at 15, 10, 5 and 1 minute before an update. A failed automatic attempt is not repeated for the same build—retry manually, or turn the option off and on.
- Per-server **Server Management… → Automation** supports daily, every-N-days and weekday schedules in local time. Choose warnings, skip when occupied, or wait until empty. The manager must remain open; stopped servers stay stopped. The next run appears in each server’s menu. Restarts save worlds and refresh join codes; `logs/maintenance.log` records their reason and outcome.
- **Server Management…** shows performance graphs and connected players, with confirmed kick/ban/unban controls. Ban changes persist across restarts.
- During server updates, the menu bar immediately shows **Stopping → Updating → Starting**, including update percentage when reported. The progress window shows the current operation and elapsed stage time.
- The manager checks GitHub for stable app updates on launch and every six hours. Its top menu line stays grey with **Up to date**, or becomes clickable with **Update Available**. Clicking downloads and verifies the signed, notarized app, saves and stops running servers, installs the update, and reopens the manager. Previously running servers and those with auto-start enabled restart afterward. **Refresh Status** also checks for manager updates.
- To update manually, open a newer downloaded app and choose **Update & Open** to replace the installed manager while preserving profiles and worlds. If hosting, **Save, Stop & Update** saves and stops all running servers first. After a successful app update, each server starts if its auto-start setting is enabled or it was running before the update.
- Intel and Apple Silicon app binaries; macOS 13 or later.
- Multiple servers can run simultaneously, each with separate world files, logs, status, and startup preferences. New servers default to different UDP port pairs; conflicting active ports are rejected.
- Copy-only imports of a one-world ZIP, modern world folder, or legacy `.db` with matching `.fwl`.
- World presets, modifiers, saving/backup settings, and admin/ban/allow lists, with underlined hover help.
- Each server has a compact submenu with Start/Stop, join-code copy and **Server Management…**. Settings, login startup, logs and confirmed deletion live in the management window. Deleted saves/settings are retained in a recovery folder.
- Imported world settings are displayed from the latest completed save without becoming launch overrides.
- Status light and last-reported player counts.
- Graceful Save & Stop; the app does not force-kill a server after a save timeout.
- Separate settings for opening the manager and starting each server at login. Running server settings remain viewable in read-only mode.
- An idle-sleep assertion while hosting. Closing a laptop lid or logging out can still stop hosting.

## How it works

The app and background service are Swift executables built from this repository; there are no third-party Swift package dependencies. The runtime and worlds are separate from the app bundle:

```text
~/Library/Application Support/Valheim Server Monitor/
  profiles.json       # settings and passwords, mode 0600
  worlds/<profile>/   # a separate save directory for each profile
  runtime/           # SteamCMD and the native server downloaded from Valve
  logs/               # shared tools and original server logs
  servers/<profile>/  # additional servers’ process state and logs
  deleted-servers/    # recoverable deleted saves and settings
```

Server control uses an app-owned record containing the PID, executable path, and process start time. It does not stop servers by a broad process-name match. Development uses an explicit isolated `VSM_HOME`; login-item mutations are disabled there. Existing CrossOver installations, third-party servers, and their launch agents are not discovered, modified, or migrated.

## Current limits

- Login startup runs after a user signs in, not before login. Hosting ends on logout or shutdown.
- Player counts come from server logs and may be stale or unavailable. This is not a live player-query protocol or an in-game activity audit.
- Some world modifiers persist in saves. An unchecked flag does not remove a previously saved modifier. The profile editor explains this behavior.
- Imports check packaging and required files, not every world chunk's internal integrity. Import from a stopped source server or a consistent backup.
- No automatic migration, mod manager, remote server control, or CrossOver backend.
- The app asks before installing Rosetta. Installing it accepts Apple's license and may require macOS authorization.
- Updates are manual and require stopping all app-managed servers because they share one runtime. One previous server runtime is retained for recovery; world backups are handled by Valheim.

## Build

Install Xcode or its command-line tools, then:

```sh
swift test
scripts/build.sh
```

The universal app and ZIP are written to `dist/`. See [release instructions](docs/RELEASING.md) for Developer ID signing and notarization.

## License and attribution

The manager code and its original server/mountain icon are MIT licensed. This is an unofficial community tool, not affiliated with Iron Gate, Coffee Stain, Valve, or Apple. Valheim and SteamCMD are downloaded from Valve and remain subject to their owners' terms; their binaries, game assets, and logos are not distributed in this repository or the app ZIP.

Server flags follow the [official Valheim dedicated-server guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/). The native launcher is inspected from Valve's dedicated-server app **896660**, macOS depot **896663**. See [verification notes](docs/VERIFICATION.md) for tested behavior and remaining checks.

### Managed server support (development)

New servers automatically install a source-built BepInEx package and the manager's RCON companion on first start. Each profile has a stable, separate runtime under `management/<profile-id>/runtime`, a private credential and a localhost-only automatically allocated RCON port. Existing profiles remain unchanged until you choose **Enable Server Management** while stopped.

Open **Server Management…** from a server’s submenu for performance, management tools, startup options, scheduled restarts, and player moderation. Server settings, logs and deletion are also available there. Status refreshes automatically; there is no manual refresh button.

The **Performance & Tools** tab shows game version, players, uptime, and graphs for **Server Gameplay Loop Update Frequency** and managed memory. Graphs have numbered gridlines and local-time labels. The manager samples each managed server once per second and keeps the last hour in memory, including while management windows are closed. Quitting the manager clears this history; unavailable readings and restarts appear as gaps. Player moderation and messaging have their own tabs.

The manager carries a pinned, tested management package. When an updated manager supplies a newer package, it schedules a warned management restart independently of Valve server updates. It does not install arbitrary upstream BepInEx releases automatically. Package hashes are verified, config/credentials are preserved, and the previous runtime is retained. A failed management startup is stopped and rolled back where a previous runtime exists; that failed package/build is blocked from repeated retries. Worlds are stored separately and never replaced by a management package.

To build management components from source, install .NET 8 and set `GAME_MANAGED_PATH` to the native server's `Data/Managed` folder, then run `scripts/build-management.sh`. No game DLLs are redistributed. See `Companion/` for the manager-owned MIT-licensed RCON source.

Existing servers with no management preference receive BepInEx and the manager’s RCON companion automatically while stopped. Running servers wait until they stop or restart. An explicit choice to disable tools is preserved. Worlds and server settings are retained; players need no client mods for these management features.
