# Changelog

## 0.1.1 — native preview

- Normalize macOS executable path aliases before checking process ownership, so status works consistently from temporary and alternate installation locations.
- Add a regression test that also rejects reused PIDs with a different start time.

## 0.1.0 — native preview

- Native-only macOS menu bar server manager with an automatic Valve download flow.
- Independent profiles, fresh worlds, copy-only imports, and detailed setting help.
- Owned-process background lifecycle, graceful saving shutdown, crossplay join code, and log access.
- Separate server and monitor login-start settings.
- Universal app build, MIT source license, unit tests, isolated native integration harness, and GitHub CI/release workflows.

The initial preview is not notarized. Remote-player, Intel hardware, and reboot/login checks remain part of stable-release qualification.
