# Valheim Server Manager for Mac

Host Valheim worlds for your friends from your Mac. This native macOS menu bar app downloads the dedicated server, creates or imports worlds, and runs multiple servers without leaving a terminal open.

**[Download for Mac](https://github.com/GlacianNex/valheim-mac-server/releases/latest)** · [What's new in 1.2.5](docs/releases/1.2.5.md) · [Setup and recovery](docs/SETUP.md)

Requires **macOS 13 Ventura or later**. The download includes Apple Silicon and Intel binaries and is Developer ID signed and Apple-notarized. No running Steam client, Steam account, CrossOver or separate plugin installation is needed.

## What it does

- **Create and import worlds.** Choose a seed, adjust world settings, or import a copy of an existing save. Imported settings and seeds are visible in the manager.
- **Run multiple servers.** Each has its own world, ports, logs, player status and startup settings.
- **Schedule restarts.** Pick a local time and daily, every-N-days or weekday schedules. Warn players, wait until empty, or skip an occupied server.
- **Manage players.** See connected players, select someone to kick or ban, review bans, and send messages to everyone on a server.
- **Watch performance.** One-hour graphs show gameplay loop update frequency and managed memory, sampled every second.
- **Keep servers current.** Get notified about official Valheim updates or enable automatic updates with player warnings and a save/stop/update/restart sequence.

## Get started

1. Download and unzip **Valheim-Server-Manager-for-Mac.zip**. Open the app and let it copy itself into Applications, or drag it there yourself. macOS may show its normal first-open confirmation.
2. In the setup window, choose **Install Native Server**. The app downloads the server from Valve. On Apple Silicon, Valve's download tool may need Rosetta; the app asks before installing it. The game server itself runs natively.
3. Choose **New Server…**. Give it a name, optionally set a world seed or import a save, and choose whether to **List my server**. Listed servers require a password; unlisted servers can have an empty password. A blank seed creates a random world.
4. Hover over the server in the menu and choose **Start Server**. Once it is online, copy its join code to share with friends.

Crossplay is enabled by default and uses Valheim's relay networking. Steam-only hosting requires forwarding the chosen UDP port and the next port on your router. Each simultaneous server needs its own unused port pair.

Allow at least **6 GB** for setup, plus space for world saves, each managed server's runtime and its rollback copy. APFS clones reduce physical disk use where available.

## Server Management

Open a server's submenu and choose **Server Management…**. The menu stays compact; the window contains:

- **Performance & Tools:** game version, uptime, performance graphs and management-tool controls.
- **Automation:** start that server at login and configure scheduled restarts. The next scheduled restart is also shown in Performance & Tools.
- **Players & Moderation:** connected players, saved bans and confirmation-based Kick, Ban and Unban controls. Ban changes persist across restarts.
- **Messages:** send a chat message from **Server** and a center-screen notification to everyone connected to that server.

The same window has buttons for server settings, logs and deletion. Settings remain viewable while a server runs, but editing requires stopping it. Deleted worlds and settings are kept in a recovery folder.

<img src="docs/images/server-performance-1.2.4.png" alt="Performance graphs with continuous lines, numbered gridlines and local timestamps spanning one hour" width="680">

*Performance graphs in 1.2.4, shown with sample data. Gaps indicate unavailable readings.*

The manager collects readings while management windows are closed. Keep the manager running in the menu bar to retain the last hour; quitting it clears this in-memory history. Gameplay loop frequency measures server simulation updates, not client graphics FPS. Managed memory excludes native allocations. Player pings are omitted because crossplay does not expose a reliable measurement through this interface.

## Restarts and updates

**Scheduled restarts** affect one server. They save the world before restarting and leave deliberately stopped servers stopped. When warnings are selected, players see them in chat and on screen at **15, 10, 5 and 1 minute**. The maintenance log records the restart reason and the join code reported after startup. Keep the manager running for schedules to work.

**Official Valheim server updates** are checked at launch and every **10 minutes**. A yellow **!** in the menu bar and beside **Update Valheim Server…** indicates a newer build. The grey **Valheim Server Build** row shows Valve's installed Steam build ID.

Enable **Automatically Update All Valheim Servers** to install new stable builds automatically. It is off by default and preserves your choice on upgrade. All worlds share the official server installation, so an update coordinates all running servers: warn players, save, stop, update, then restart those that were running. Without working management tools, automatic updates wait until servers are confirmed empty; unknown player counts block the update. Progress follows **Stopping → Updating → Starting**.

**Manager app updates** are separate. The top menu line checks GitHub at launch and every **six hours**. It stays grey when up to date and becomes clickable when **Update Available** appears. Clicking downloads and verifies the new app, saves and stops hosted servers, installs the update and reopens the manager. Previously running servers and servers marked for auto-start restart afterward. You can also open a newer downloaded app and accept its update prompt.

For cancellation, failed updates and rollback, see [setup and recovery](docs/SETUP.md).

## Management tools are included

The app bundles a tested BepInEx loader and its own RCON companion for warnings, performance, messaging and moderation. These tools do not change gameplay rules, and players do not need client mods. Each server has a separate managed runtime and a private, authenticated connection accessible only on this Mac.

- New servers install the tools on first start.
- Existing servers without a previous management preference get them automatically while stopped after updating the manager. Running servers wait until they stop or restart.
- An explicit choice to disable tools is preserved. Change it in **Server Management → Performance & Tools** while stopped.

Compatible tool updates ship with manager updates and are applied automatically for enabled servers, using warned maintenance when a restart is needed. The app does not fetch arbitrary upstream BepInEx releases. It verifies package hashes, preserves configuration and credentials, and retains the previous runtime for recovery. Worlds remain separate from tool installations.

General community mod browsing, importing and installation are **not included** in this release.

## Saves, storage and hosting limits

Data stays outside the app bundle, so replacing the app preserves your worlds and settings. The directory retains its original name for compatibility:

```text
~/Library/Application Support/Valheim Server Monitor/
  profiles.json        # settings and passwords; owner-readable/writable only
  worlds/<profile>/    # world saves
  runtime/             # SteamCMD and the shared official Valheim server
  management/<profile>/ # isolated managed runtime, tools and credentials
  logs/                # shared tools, maintenance and original server logs
  servers/<profile>/   # additional servers' process state and logs
  deleted-servers/     # recoverable deleted worlds and settings
```

Imports copy a one-world ZIP, modern world folder, or legacy `.db` with its matching `.fwl`. Use a consistent backup or stop the source server first. Imports check required files and packaging, not every world chunk. Saved world modifiers can persist; the editor explains when a setting inherits from the save rather than overriding it.

The manager controls only its own servers, identifying them by PID, executable path and process start time. It does not discover or take over independent servers or CrossOver installations. It prevents idle sleep while hosting, but closing a laptop lid, logging out or shutting down can interrupt hosting. Login startup happens **after a user signs in**, not before login. Quitting the manager leaves servers running, but stops monitoring, scheduled restarts and automatic updates until it reopens.

Menu-bar player counts use the latest count reported in server logs and may be stale or unavailable. The management window queries connected players through the companion. This is not an in-game activity history or a remote administration service.

Native runtime tests run on Apple Silicon; the Intel app has also been tested under Rosetta. Physical Intel and macOS 13 hardware coverage remains pending. See [verification and coverage limits](docs/VERIFICATION.md).

## Build and contribute

Use macOS with a current Xcode/Swift toolchain. Unit tests do not need downloaded game files:

```sh
swift test
```

To package the full app, also install **.NET 8** and provide the native Valheim server's reference assemblies:

```sh
export GAME_MANAGED_PATH="/path/to/server/valheim_server/Data/Managed"
scripts/build-management.sh
scripts/build.sh
```

The universal app and ZIP are written to `dist/`. Source builds are development artifacts unless you configure Developer ID signing and notarization. Follow [contributing instructions](CONTRIBUTING.md) for isolated development with `VSM_HOME`, and [release instructions](docs/RELEASING.md) for distribution.

## License and attribution

The manager, its original icon and its RCON companion are MIT licensed. Bundled third-party management components retain their own licenses and notices; the package includes those notices and Doorstop's corresponding source. Valheim and SteamCMD are downloaded from Valve, not redistributed in the app ZIP. No game assets, game DLLs or Valheim logos are bundled.

This is an unofficial community tool, not affiliated with Iron Gate, Coffee Stain, Valve or Apple.
