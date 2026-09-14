# First public release

## Acceptance
A downloaded macOS app can install the native Valheim dedicated server from Valve, create or copy-import a world, start/stop it safely, show status/last reported players/join code, open logs, and manage login startup without a terminal or Python. Only this app's own server processes and data may be changed.

## Tasks
- [x] Portable Swift core: app-owned paths, durable profiles, validation, copy-only world import, file locks.
- [x] Native installer: official SteamCMD download, Rosetta prerequisite flow where necessary, progress and retry, executable validation.
- [x] Native lifecycle: exact process ownership, port checks, graceful shutdown, fresh session logs, background service.
- [x] First-run UI: install progress, create/import profile, clear help, error recovery, separate monitor/server login toggles.
- [x] Preserve user data: isolated development root; no migration or changes to the existing private installation.
- [x] Focused unit and isolated native integration tests; verify original server remains online.
- [x] Original icon, universal app packaging, reproducible builds, CI and release workflow.
- [x] GitHub repository, open-source license, setup/contribution/security docs, release notes and downloadable preview.

## Boundaries
Native macOS is the first-release runtime. CrossOver remains available through the user's existing installation; automatic migration and managing third-party running servers are deferred. Do not copy existing credentials, saves, logs, branding, or personal paths into source control. No changes to the installed Valhiem Server Monitor app or its launch agents. Public distribution must state whether its binary is notarized; never claim signing that was not performed.

## Stable-release follow-up
- [ ] Supply a Developer ID Application certificate and notarization credentials; validate a clean download on another Mac.
- [ ] Verify a real remote player joining/leaving, Intel hardware, and a reboot/login cycle.
