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

**Valheim Server Build** occupies its own section because all hosted worlds share the installation. The number is Valve’s Steam build ID, not the game’s marketing version. Checks run at launch and every 15 minutes using a separate downloader copy; checking leaves running servers untouched.

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
