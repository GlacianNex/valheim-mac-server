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

## Release 0.1.8 signing checks — 2026-09-14

- Universal app signed with Developer ID Application, hardened runtime, and a secure timestamp.
- Apple accepted notarization submission `9baf4c9e-ba39-4b84-926b-7843f29bc951`; the ticket was stapled before packaging the final ZIP.
- The final ZIP was extracted into a separate directory. Signature and stapled-ticket validation passed, and local Gatekeeper assessment returned `Notarized Developer ID`.
- This release changes distribution signing, not server behavior. The running installed server was not restarted or replaced.

## Release 0.1.9 app-update restart checks — 2026-09-14

- Apple accepted submission `3bbb1370-87aa-4cf1-a06e-beddc72f2ad8`. The extracted final ZIP passes signature, stapled-ticket, and local Gatekeeper validation.
- 33 Swift tests pass. Regression checks cover all combinations of prior running state and auto-start preference, same-profile restart without changing saved settings, rejection of a changed or missing profile, and propagation of startup errors.
- The updater passes the selected profile to the installed app only after successful replacement. The installed app requests startup through its normal service controller and shows immediate Starting feedback.
- A stopped server with auto-start disabled stays stopped. Auto-start enabled starts the selected server even if it was stopped before updating.
- An actual Applications replacement while hosting remains to be tested end to end; the live server was not interrupted for development testing.

## Remaining stable-release checks

- Browser-download first launch on another Mac, without removing quarantine or using Open Anyway.
- A real remote player joining and leaving; log-based counts are not an authoritative live query.
- Intel hardware runtime validation (the binary builds for Intel; the local runtime test is Apple Silicon).
- A real logout/reboot/login cycle and macOS background-item permission variations.
- Longer-running, populated worlds and recovery from network outages.

These are release qualifications, not claims that were inferred from a successful build. Keep the app a preview until the relevant checks are completed.
