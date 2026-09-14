# Mac setup and recovery

This guide is for hosting a Valheim dedicated server on **macOS 13 Ventura or later**. The app includes Apple Silicon and Intel binaries; runtime testing is currently on Apple Silicon. Have about 6 GB of free disk space available. On Apple Silicon, Valve's download tool may need Rosetta; the app offers to install it. The dedicated server itself runs natively.

## First run

Fresh installations use `/Applications/Valhiem Server Manager for Mac.app`. Upgrades from the former Valheim Server Monitor keep their existing app folder path so registered login items continue to work. Both display the new manager name. Its copy-to-Applications prompt helps establish a stable launch path. To update, download and unzip a newer release and open the downloaded app. Starting with 0.1.4, the download offers **Update & Open** when an older version is installed. If its server is running, **Save, Stop & Update** saves and stops it first; players disconnect, and you start the server again afterward. The app validates the new copy, closes the old manager, replaces it, and reopens from Applications. Profiles, worlds, settings, and login preferences are stored separately and preserved. If macOS brings the old manager forward instead, quit it and open the download again. This installs a manually downloaded release; it does not check for releases or download app updates automatically.

Setup downloads roughly 2 GB from Valve, with additional disk space needed during verification and updates. Crossplay is enabled by default. Select **Open Manager at Login** and **Automatically Start Server at Login** separately in the menu. Enabling server autostart while stopped takes effect on a future boot/login; it does not immediately start the server.

The macOS login service identifiers are:

- `io.github.glaciannex.valheimservermonitor.menu`
- `io.github.glaciannex.valheimservermonitor.server`

Other launch agents are never modified. macOS may list these items under Login Items / Allow in the Background. Disabling them there can prevent automatic startup.

## Valheim server updates

The menu's **Server build** row shows the installed Steam build number. This identifies the exact installed release; it is not Valheim's marketing version number. The manager checks Valve's public (stable) branch at launch and every 15 minutes. These checks use a separate copy of Valve's downloader and leave the running server and its libraries untouched.

When a newer build is available, click the row and confirm **Update Server**. A running server saves and stops, the latest stable build is installed, and the same selected world is restarted after success. Players disconnect during this update. A stopped server stays stopped. If installation fails, the manager shows the error and does not attempt a restart. Profiles and world data are preserved.

Click an up-to-date row to check again, or retry when a check is unavailable. Technical check details are in `version-check.log`; update progress is in `installation.log`. App updates and Valheim server updates are separate operations.

## Existing worlds

Stop the source server or choose a consistent backup before importing. Select a ZIP containing exactly one world, a modern world folder, or a legacy `.db` with its adjacent `.fwl`. Set World filename to match the imported folder/file name. The import is copied into a new profile. The source remains untouched.

An empty profile creates a fresh world on its first start. To choose a particular seed, create a world in Valheim and import it. Switching or editing the active profile requires Save & Stop first.

## Startup trouble

Open the logs folder from the menu. Every run has a separate server log and console log; installation progress is in `installation.log`. The menu shows the last startup error when available.

- **Port already in use:** choose another base port or stop the other server through its own manager. This app will not stop it for you.
- **Download failed:** check connectivity/free space, then use Set Up / Update Native Server to retry.
- **Rosetta missing:** approve the Rosetta prompt if you accept Apple's license. This is for Valve's downloader, not the native server.
- **Unknown player count:** the server has not reported a count in a recognized log line yet.
- **Save timeout:** inspect the current server/console log. Do not force-quit a server that is still writing a save.
- **Profile won't import:** verify it contains one complete world, has matching filenames, and has no symbolic links or unsafe archive paths.

For crossplay, use the reported join code or public server address; a LAN or loopback address is not the crossplay connection route. Steam-only hosting needs router forwarding for both UDP ports. The computer needs an active network connection and must remain logged in. The service prevents idle sleep while hosting, but it cannot host while the Mac is shut down or sleeping with its lid closed.

## Removing the app

Save & Stop the server, disable both login options, and quit the manager. Remove only this app's two launch-agent files listed above from `~/Library/LaunchAgents` if you want to remove all startup registration. Keep `~/Library/Application Support/Valheim Server Monitor/worlds` until you have backed up your worlds. Deleting the app bundle alone does not erase world data.
