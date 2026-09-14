# Verification

## Local evidence — 2026-09-14

Test host: Apple Silicon, macOS 26.6.2. Tests use isolated application roots and disposable worlds on a separate UDP port pair.

- 18 Swift unit tests pass: profile preservation, unchanged selection on creation, immutable world filenames, validation, literal argument passing, modifier round-trip, modern/ZIP copy imports, rejection of symlinks/incomplete imports, private file permissions, unrelated-process protection, canonical macOS executable-path aliases, active-service locking, occupied-port rejection, isolated login-item guards, and last-reported player parsing.
- The app installer downloads SteamCMD and dedicated-server app 896660 anonymously, validates the native executable's signature and both Intel/Apple Silicon slices, and installs into its own runtime directory.
- The Steam server depot does not include `steamclient.dylib`. The service uses the universal Steam client libraries already supplied by SteamCMD through a private `DYLD_FALLBACK_LIBRARY_PATH`. It does not install or launch the Steam app.
- A native test world reaches an active crossplay session with a join code and zero players.
- Two complete lifecycle cycles pass: native startup, SIGINT shutdown, all five save stages completed, a reload of the saved chunks, and save number 2.
- Universal app packaging and ad-hoc signature verification pass.
- First-run setup and profile-editor screenshots were inspected. A disposable profile was entered and saved through the native UI; underlined help and field values displayed correctly.
- A uniquely named temporary launchd job successfully started the native server via RunAtLoad, followed by a clean stop and removal of that job. Existing login items were not changed.
- GitHub macOS CI passed all unit tests and built/uploaded the universal app.
- The developer's unrelated existing server remains running. Its installed monitor, profile configuration, and existing launch-agent files are checked separately for unchanged content.

## Preview 0.1.2 checks — 2026-09-14

- 24 Swift tests pass, including copy quarantine handling (source and external link targets preserved), existing-install refusal, readable SteamCMD progress, and automatic fresh-world filenames without renaming existing worlds.
- On the local Mac, the actual Copy to Applications & Open button installed the public app and opened setup. Quitting and reopening that installed copy did not repeat the location prompt. No server installation or startup was performed during this check.
- Universal packaging and ad-hoc signature verification pass. The clean browser-download Gatekeeper path still needs verification on another Mac; this preview is not notarized.

## Before a stable release

### Preview 0.1.4 update checks

- 26 Swift tests pass, including failed-replacement rollback, successful backup preservation, and rejection of older, unrelated, or unsigned update bundles before quitting the installed monitor.
- The actual Update & Open action replaced the running public 0.1.2 monitor with 0.1.4 and reopened setup from Applications. The installed bundle version and executable path were checked. No game server was started for this UI test.
- Universal build passes. Updating while hosting still needs an end-to-end test with a disposable running server; it uses the existing graceful-stop path and requires the server lock before replacement.

## Remaining stable-release checks

- Developer ID signing, Apple notarization, and clean-download Gatekeeper verification.
- A real remote player joining and leaving; log-based counts are not an authoritative live query.
- Intel hardware runtime validation (the binary builds for Intel; the local runtime test is Apple Silicon).
- A real logout/reboot/login cycle and macOS background-item permission variations.
- Longer-running, populated worlds and recovery from network outages.

These are release qualifications, not claims that were inferred from a successful build. Keep the app a preview until the relevant checks are completed.
