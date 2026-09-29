# 1.3 — Mods, World Controls, and Better Server Visibility

Released September 29, 2026 · Changes since 1.2.5

## TL;DR

- **Install and manage mods inside the manager.** Browse the catalog, install dependencies, toggle mods per server, and see which plugins loaded or failed.
- **More control over your world.** Send messages, configure welcome messages, manage backups, skip time, and control raids.
- **Better connection and performance visibility.** Share an IP address and port for Steam-only servers, view player ping graphs, and optionally enable network optimization mods.
- **A much better log viewer.** Separate server logs from manager activity, filter text, refresh every second, toggle wrapping and auto-scroll, and copy text without line numbers.
- **A clearer management window.** Always-visible server status and mod switches, dedicated Mods and Backups tabs, and restart countdowns you can cancel, accelerate, or close.

## Features

### Mod catalog and installation

- Added a per-server **Mods** tab and **Open Mod Catalog** button.
- Browse Thunderstore and Hexium, search packages, sort by downloads, rating, or name, and choose available versions.
- Read descriptions, installation instructions, dependencies, and available client-install requirements before installing.
- Install from the catalog or import a ZIP, folder, or DLL with **Install from File…**. Installation enables the selected mod and its dependencies for the next server start.
- Resolve declared dependencies automatically. Reuse dependencies already installed at a sufficient version, including the native BepInEx framework supplied by the manager.
- Show installed packages in the catalog. Bundled components are identified as supplied by the manager rather than offered as duplicate installations.
- Hide known incompatible and client-only packages, along with standalone mod managers such as r2modman. Missing compatibility metadata does not hide every otherwise eligible package, and catalog inclusion is not a guarantee that a mod works on macOS.
- Keep each server's mod selection separate. Stage deployments, track installed files, and preserve configuration files when rebuilding the managed runtime.
- Enable required dependencies automatically and block disabling a dependency that another enabled mod still needs.

### Mod status and bundled tools

- Added an activation checkbox separate from each mod's runtime status, plus name, version, and **Client** columns.
- Show enabled/disabled selections while stopped and loading evidence, failures, and attributed runtime errors while running. Merely finding a DLL does not count as successful loading.
- Show pending activation changes that will take effect on restart. Manually copied plugin DLLs also appear in the inventory.
- Bundled mod rows are read-only, with hover help directing users to the switches at the top of Server Management.
- Added **Jötunn 2.30.2** to the shared framework alongside BepInEx. The manager's RCON companion provides management features; custom mods may have additional requirements.
- Added independent **Server Management Mods** and **Network Optimization Mods** switches, with the included components listed underneath.
- Added optional **NetworkPerformanceSystem 1.6.0**, disabled by default. It changes networking behavior; improvements depend on the server and players and are not guaranteed.
- Added a player-limit setting in **World Settings**. The default preserves Valheim's normal capacity and is recommended for performance; overriding capacity requires the networking tools.

The **Client** column highlights detected player-install requirements, including requirements inherited from dependencies. A **No** value means no requirement was detected; it is not proof that an unmodified client is compatible. Check the mod's instructions when metadata is incomplete.

### World control and backups

- Expanded **World Control** into Messages, Time, and Raids.
- Broadcast a message to everyone on the server and configure a private welcome message for joining players.
- Skip to the next morning or advance **3, 6, or 12 in-game hours**, with confirmation before changing world time.
- Start a selected raid near a connected player, stop the current raid, or pause new raids for **15, 30, 60, or 120 real minutes**.
- Use readable raid names instead of internal identifiers.
- Added a dedicated **Backups** tab for world saves, named backups, and restoration while stopped. Restoring creates a recovery backup first.

Time changes can advance world timers. Stopping a raid leaves creatures already spawned alive. A raid pause expires automatically or ends when the server restarts.

### Connections, performance, and moderation

- Show a copyable public IP address and server port when crossplay is disabled. Router forwarding is still required for friends connecting from outside the local network.
- Added **Performance → Ping**, with a separate latency graph for each connected Steam player and one-hour background history while the manager is running.
- Disable Ping for crossplay servers, with the explanation: **“Ping is only available with CrossPlay turned off”.** Missing samples appear as gaps rather than zero latency.
- Moved administrator and permitted-player management into **Moderation**, alongside existing player and ban controls. Removed the duplicate Access List section from World Settings.

### Management window and logs

- Keep status, player count, version, and uptime above the tabs, with a colored status indicator and a first-start explanation when applicable.
- Place both bundled-mod switches above the tabs so they remain accessible throughout the window.
- Rename **Performance & Tools** to **Performance**, **Players & Moderation** to **Moderation**, and **View Settings…** to **World Settings**.
- Add Start/Stop Server alongside the other bottom-row actions, plus **Server Folder** access from Mods.
- Add **Start Server on Login** to the server submenu, synchronized with the setting in Server Management.
- Replace the external log-opening flow with an integrated **Server Logs** window, split into **Server** and **Manager Activity**.
- Filter displayed lines, refresh every second, and quickly toggle **Auto-scroll** and **Wrap Text**.
- Add a separate line-number gutter so wrapped continuations are distinguishable from new lines. Normal text selection and Copy preserve the text's line breaks without copying gutter numbers or adding visual wrap breaks.
- View the latest 256 KB per log view and open the log folder directly.

### Experimental builds

- Add a clearly labeled **Experimental** build channel for local testing without increasing the public release version for every build.
- Allow Experimental builds to replace stable or earlier Experimental installations while retaining signature checks and the existing installation flow.
- Keep public manager-update checks disabled while using Experimental. Official Valheim server-update checks remain separate.

## Bug Fixes

### Installation and dependencies

- Fixed dependency resolution treating the manager-supplied **BepInExPack_Valheim** equivalent as a missing package, prompting unnecessary downloads or blocking dependent installs.
- Fixed dependency planning to recognize sufficient installed versions and distinguish packages to download from packages already supplied or installed.
- Corrected deployment folder handling and assembly resolution for supported package layouts. These fixes apply across packages rather than patching individual third-party mods.
- Improved failure reporting when a required dependency cannot load, so dependent plugins are not incorrectly presented as healthy.
- Improved catalog description and installation-instruction retrieval and formatting, including Markdown markers, HTML fragments, headings, links, and table formatting.
- Corrected overly restrictive catalog filtering that left only a small number of visible mods.

### Controls, restarts, and status

- Fixed custom mod rows being unselectable. Activation is now controlled directly by each row's checkbox; bundled rows remain controlled by the top-level switches.
- Fixed missing pending-change feedback after cancelling a restart. Cancelling the countdown leaves the saved mod selection in place for the next start.
- Added **Cancel**, **Restart Now**, and window-close controls to the restart countdown. Closing hides the window without cancelling the countdown; progress can be reopened.
- Fixed restart countdowns locking users out of unrelated server-management controls. The manager revalidates server state before maintenance begins.
- Fixed stale **Starting** status after manually stopping a server configured to start at login.
- Improved player-count reporting for Steam-only servers and handled unavailable ping measurements without inventing zero values.
- Prevented network optimization from silently changing server capacity to 60 players. The normal player limit is preserved unless explicitly overridden in World Settings.
- Improved disabled-state handling for controls that require management tools or a running server.
- Cleaned up mod-table alignment, status-column sizing, bundled-mod hover hints, and the **Mod Selection Unchanged** dialog.

The compatibility investigation covered the top 500 mods, with native server startup and log checks and follow-up investigation of failures. It informed general manager and installer fixes; third-party mods were not modified. Successful startup is not proof of complete gameplay compatibility, client compatibility, or compatibility between combinations of mods. Some packages still fail because of their own runtime or platform requirements.
