# Verification and coverage

## Release 1.0.0

Test host: Apple Silicon Mac, macOS 26.6.2. Development and native integration tests use isolated data roots, disposable worlds, and separate UDP ports. The production server is not used as a test world.

- 44 automated tests cover profile/world preservation, argument validation, imports, process ownership and exit detection, independent server state, runtime locking, port conflicts, database migration, update replacement/rollback, saved-setting reads, password rules, and recoverable deletion.
- Two native crossplay worlds reached Online simultaneously with different join codes. Stopping one left the other Online with an unchanged process record. Both saved and stopped cleanly. These checks passed with the Developer ID signed app and reloaded test worlds.
- Shared runtime installation was refused during hosting. Native installation, graceful save/stop/reload, and startup through a temporary isolated launchd job were exercised during development.
- Modern and legacy import tests verify that settings are displayed without adding launch overrides, and incomplete newer save generations are ignored.
- Native tests verified that an empty password works for an unlisted server; public listing with an empty password is rejected by Valheim.
- The maintainer confirmed the local updater fix and subsequent UI build worked, then approved 1.0.0 publication.
- Apple accepted the 1.0.0 submission on 2026-09-14; signature, stapled-ticket, and Gatekeeper checks passed on the extracted release ZIP.
- Release packaging builds both architectures, uses hardened runtime and a secure timestamp, and requires Apple acceptance, ticket stapling, signature verification, and Gatekeeper assessment before publication.

## Coverage limits

Intel hardware runtime testing, a full multi-server reboot/login cycle, and a future Valve runtime update with multiple populated servers have not been independently exercised. Universal compilation is not an Intel runtime test. Tests do not verify every in-game modifier effect or internal world chunk. Player counts are last-reported log values, and inherited settings reflect saved metadata rather than live console state.

Apple notarization checks distribution integrity and malicious content; it is not App Store review or a code-quality certification. Keep these limits distinct from the 1.0.0 release label.

## Release 1.1.2

See [seed support](SEEDS.md) for 50 passing tests, seeded native lifecycle checks, and biome-cache equivalence evidence. The maintainer confirmed the combined 1.1.2 build worked and approved publication. The release uses that same signed and notarized ZIP.

### Player-count correction

The menu polls once per second. The parser now processes player-count announcements and `Connections N ZDOS:` snapshots in log order. A `Player connection lost` announcement invalidates the count because PlayFab retains the disconnected socket while reconnecting. The aggregate count stays unknown if any running server has an unknown count. Later valid announcements/snapshots restore it. Regression checks cover loss, zero snapshots, remaining players, rejoining, and unknown aggregates. Read-only replay against the two running servers' logs returned zero for both, matching the user's observation. No server restart was needed for this verification.

### Stopping status

An isolated service-lock/stop-request regression reproduced the incorrect aggregate Starting state before the fix, then passed with Stopping afterward. Aggregate-state tests cover stopping alongside online or starting servers, normal online state, and all stopped. All 51 tests pass. The menu title and tooltip now prioritize Stopping… during shutdown. Production servers were not stopped for these checks.

## Unreleased installer and long-log fixes

On macOS 27.0 build 26A428, the old combined lipo command failed for the native executable and four Steam libraries. Separate arm64 and x86_64 checks passed for all five. Tests also reject binaries missing either architecture. An isolated full SteamCMD validation/installation completed with the corrected installer, preserving the previous runtime in its backup directory. No production installation was replaced.

A production log exceeding 250 KB reproduced the readiness-marker loss: the server continued saving while the old monitor reported Starting. The corrected monitor recovered Online from the same log without restarting the server. Incremental reading is process-local and changes no profile, service-record, or world format. Tests cover long logs, reconstruction after a manager restart, partial log writes, lost connections, updated join codes, truncation, replacement and missing logs.
