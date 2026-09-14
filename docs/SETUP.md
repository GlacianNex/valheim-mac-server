# Setup and recovery

## First run

Keep the app in `/Applications/Valheim Server Monitor.app`. Its copy-to-Applications prompt helps establish a stable launch path. If that exact app already exists, open it or use Finder to replace it when updating. Application updates do not delete the separate world directory.

Setup downloads roughly 2 GB from Valve, with additional disk space needed during verification and updates. Crossplay is enabled by default. Select **Open Monitor at Login** and **Automatically Start Server at Login** separately in the menu. Enabling server autostart while stopped takes effect on a future boot/login; it does not immediately start the server.

The macOS login service identifiers are:

- `io.github.glaciannex.valheimservermonitor.menu`
- `io.github.glaciannex.valheimservermonitor.server`

Other launch agents are never modified. macOS may list these items under Login Items / Allow in the Background. Disabling them there can prevent automatic startup.

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

Save & Stop the server, disable both login options, and quit the monitor. Remove only this app's two launch-agent files listed above from `~/Library/LaunchAgents` if you want to remove all startup registration. Keep `~/Library/Application Support/Valheim Server Monitor/worlds` until you have backed up your worlds. Deleting the app bundle alone does not erase world data.
