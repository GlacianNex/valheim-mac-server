# Mac setup and recovery

Requires macOS 13 Ventura or later. The app includes Apple Silicon and Intel binaries; runtime testing has been on Apple Silicon. Allow 6 GB for the shared runtime and updates, plus space for worlds and backups. Each running world also uses memory and CPU.

## Install and create a server

1. Download the signed, notarized ZIP from [GitHub Releases](https://github.com/GlacianNex/valheim-mac-server/releases/latest), unzip, and open the app. Accept its copy to Applications or drag it there in Finder.
2. Choose **Install Native Server**. The manager downloads Valve’s server anonymously. No Steam account, running Steam client, Python, or CrossOver is needed. Valve’s installer may require Rosetta on Apple Silicon; the app offers Apple’s installer. The game server runs natively.
3. Choose **New Server…**. Enter the server names and select **List my server** if it should appear publicly. This checkbox enables Password; listed servers require at least five characters. Unlisted servers can have an empty password, allowing anyone with the address or join code to connect. Unchecking listing preserves an existing password; clear it before unchecking to remove password protection.
4. Leave World filename blank to generate it from the server name, or use **Import World…**. Save, then hover over the server’s status row and choose **Start Server**.

Each server appears independently in the menu. Its submenu contains Start/Save & Stop, join-code copy, settings, auto-start, logs, and Delete Server. Multiple servers can run simultaneously. New servers default to unused configured UDP port pairs; startup rejects conflicts with another active server. A server uses its base port and the next port.

## Import and view settings

Import from a stopped source server or consistent backup. Choose a ZIP containing one complete world, a modern world folder, or a legacy `.db` with its matching `.fwl`. The filename must match the imported world. The manager copies the source into a separate world directory; it never moves or edits the original.

Settings automatically display inherited world modifiers from completed `.fwl2` save generations or legacy `.fwl` metadata. These values remain inherited when an unrelated field is saved. They reflect the last saved metadata, not a live console query; in-game changes can appear after the next save. Unsupported or incomplete metadata is reported rather than guessed. Explicit profile overrides still take precedence in the form and apply on the next start.

Running servers offer **View Settings…** with editing disabled. Stopped servers offer **Edit Server…**. Some world keys persist in saves: unchecking a launch flag does not remove a previously saved world key. The underlined setting labels explain these effects.

**World seed (optional)** accepts 1–10 letters or digits. It is case-sensitive; blank lets Valheim choose a random seed. The seed is locked when the server record is created. Imported worlds keep their original seed, which is shown read-only in settings when the save can be read. To use another seed, create a new server. Terrain may differ across Valheim world-generation updates.


## Networking and login startup

Crossplay is enabled by default. Use the reported join code or public address; LAN/loopback addresses are not the crossplay connection route. Steam-only hosting requires router forwarding for the base UDP port and the following port. The app does not configure your router.

**Open Manager at Login** is in the main menu. **Automatically Start at Login** belongs to each server’s submenu. Enabling auto-start while stopped does not start it immediately. Startup occurs after login, not before a user signs in. Hosting requires a network connection and a logged-in Mac; the service prevents idle sleep, but cannot host during shutdown or laptop lid sleep.

LaunchAgent identifiers under `~/Library/LaunchAgents`:

- `io.github.glaciannex.valheimservermonitor.menu` — manager.
- `io.github.glaciannex.valheimservermonitor.server` — original server.
- `io.github.glaciannex.valheimservermonitor.server.<profile-id>` — additional servers.

macOS Login Items / Allow in the Background permissions can prevent automatic startup. Unrelated launch agents are not managed by this app.

## Update the app

Download and open a newer app. **Update & Open** validates and replaces the installed manager, then opens it from Applications. If hosting, **Save, Stop & Update** saves and stops all running servers first. After successful replacement, servers that were running and servers with auto-start enabled are started again. Players disconnect during replacement. Profiles, worlds, and login preferences remain separate from the app bundle.

App updates are manually downloaded; the manager does not automatically download its own releases. Fresh installs use `/Applications/Valheim Server Manager for Mac.app`. Older installations can retain `/Applications/Valhiem Server Manager for Mac.app` or `/Applications/Valheim Server Monitor.app` so existing startup paths keep working.

## Update the Valheim runtime

**Valheim Server Build** occupies its own section because all hosted worlds share the installation. The number is Valve’s Steam build ID, not the game’s marketing version. Checks run at launch and every 10 minutes using a separate downloader copy; checking leaves running servers untouched.

Click an available update and confirm **Update Server**. All running servers save and stop, the shared runtime updates, and those servers restart after success. Previously stopped servers stay stopped. A failed installation reports an error and does not attempt a restart. One previous runtime is retained for recovery. Click the row to recheck or retry a failed check.

## Logs and troubleshooting

Each server’s submenu has **Open Server Log**, **Open Logs Folder**, and its last error when available. Shared download/update logs are in `~/Library/Application Support/Valheim Server Monitor/logs/installation.log` and `version-check.log`.

- **Port conflict:** choose a different base port; the app will not stop the other server for you.
- **Download failure:** check connectivity and free space, then retry setup/update.
- **Unknown player count:** no recognized count has been reported yet; counts come from logs and can be stale.
- **Save timeout:** inspect the log. The app does not force-kill a server that is still saving.
- **Import failure:** check that exactly one complete world is included and filenames match. Symlinks and unsafe ZIP paths are rejected.

## Delete a server or remove the app

**Delete Server…** requires the server to be stopped and asks for confirmation. It removes the server record and background job while retaining world files and settings under `~/Library/Application Support/Valheim Server Monitor/deleted-servers/<recovery-id>/`. Other servers are unaffected. Recovery folders contain private settings, including passwords; do not publish them.

To remove the app, save and stop all servers, disable their auto-start settings and manager login startup, then quit. Remove only this app’s LaunchAgent files listed above if removing registration completely. Back up the application-support folder before deleting data. Removing the app bundle alone does not erase worlds.

## Upgrading older profile databases

The first settings write backs up the original single-server database as `profiles-before-multiserver.json` and writes schema 2 with independent startup preferences. Existing world directories remain in place. The original server keeps its process-state/log locations; additional servers use `servers/<id>/`.

Older managers cannot read schema 2. To roll back, stop every server, unload/remove additional per-server LaunchAgents while retaining the original server job, then restore the older app and database backup. Keep a copy of the current database: restoring the backup discards later settings and server records, though the separate world files remain. Do not run older and newer managers against the same data simultaneously.

## Scheduled restarts and management

Open a server’s submenu and choose **Server Management… → Automation**. Enable it, choose daily/every-N-days/selected weekdays, and set a local time. Choose whether to warn players, skip an occupied server, or wait until it is empty. The next run is shown in **Performance & Tools**. Leave the manager open; **Open Manager at Login** can reopen it after login. A schedule does not start a deliberately stopped server. Missed occurrences are skipped rather than replayed after the Mac wakes or the manager reopens. A restart already waiting for players can continue waiting.

Warnings appear in chat and on screen at 15, 10, 5 and 1 minute. If the manager cannot deliver warnings, an occupied server waits. You can cancel a countdown in its progress window. If you turn on warnings too late for the scheduled time, the manager gives a full 15-minute countdown instead of shortening the warning period.

Scheduled restarts affect only that server. They do not update the shared Valve installation or stop other servers. Valve updates use the separate **Automatically Update All Valheim Servers** option and coordinate all running servers. When a restart finishes, use the current join code in its submenu; the old code is hidden while stopping. The maintenance log at `~/Library/Application Support/Valheim Server Monitor/logs/maintenance.log` records outcomes and join codes.

New servers automatically get management support on first start. Existing servers without a management preference receive the tools automatically while stopped after a manager update. Running servers are left alone until stopped; restart installs the tools before launching the game. A previous explicit choice to disable tools stays off. You can change that choice while stopped in **Server Management… → Performance & Tools**. Each server gets a separate runtime and a private local management connection. **Server Management…** shows live performance and provides kick, ban and unban in **Players & Moderation**. Ban changes are saved in the profile so restarting does not undo them. Players do not need a mod for these management functions.

Management package upgrades ship with compatible manager updates. Before replacing a package the manager retains its previous runtime and preserves credentials/configuration; failed startup blocks repeated retries and restores that runtime when available. It leaves the server stopped for inspection. World saves remain separate. Check the server’s error and logs before retrying. If you need to host while investigating, clear **Enable management tools (BepInEx + RCON)** in **Server Management → Performance & Tools** while stopped and start the native server without management plugins. The preserved world remains in place; automatic restarts then require the server to be empty.

Performance graphs retain the last hour of one-second readings while the manager is running, even with all management windows closed. Reopening a window shows that server’s history. History is held in memory and clears when the manager exits. Gridlines show values; the horizontal axis shows local time. Missing readings and server restarts appear as gaps.

## Login startup reports isolated development mode

In 1.2.4 and earlier, first-time setup can incorrectly show “Login item changes are disabled when VSM_HOME is set” even when no override is set. Creating the normal data directory changes Foundation's directory URL representation, which the old isolation check mistakes for a different location.

Quit the manager, reopen it from Applications, then try **Open Manager at Login** again. Quitting the manager leaves running servers running. The source fix compares normalized paths and is intended for the next app release.

If the message persists after reopening, check whether you intentionally launched with a custom `VSM_HOME`. Keep a record of that location before changing it: reopening without the override uses the normal data directory and does not move any existing profiles or saves.
