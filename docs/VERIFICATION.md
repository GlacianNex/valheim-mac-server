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

The menu polls once per second. The parser now processes player-count announcements and `Connections N ZDOS:` snapshots in log order. The original 1.1.2 parser invalidated counts after a lost connection; 1.1.4 supersedes this behavior by retaining every reported count. The aggregate count stays unknown if any running server has an unknown count. Later valid announcements/snapshots restore it. Regression checks cover loss, zero snapshots, remaining players, rejoining, and unknown aggregates. Read-only replay against the two running servers' logs returned zero for both, matching the user's observation. No server restart was needed for this verification.

### Stopping status

An isolated service-lock/stop-request regression reproduced the incorrect aggregate Starting state before the fix, then passed with Stopping afterward. Aggregate-state tests cover stopping alongside online or starting servers, normal online state, and all stopped. All 51 tests pass. The menu title and tooltip now prioritize Stopping… during shutdown. Production servers were not stopped for these checks.

## Release 1.1.4

On macOS 27.0 build 26A428, the old combined lipo command failed for the native executable and four Steam libraries. Separate arm64 and x86_64 checks passed for all five. Tests also reject binaries missing either architecture. An isolated full SteamCMD validation/installation completed with the corrected installer, preserving the previous runtime in its backup directory. No production installation was replaced.

A production log exceeding 250 KB reproduced the readiness-marker loss: the server continued saving while the old monitor reported Starting. The corrected monitor recovered Online from the same log without restarting the server. Incremental reading is process-local and changes no profile, service-record, or world format. Tests cover long logs, reconstruction after a manager restart, partial log writes, lost connections, updated join codes, truncation, replacement and missing logs.

Before the final player-count follow-up, all 55 automated tests and the universal build passed on macOS 15 CI. On macOS 27, an isolated native world passed two start/save/stop cycles after installation, including reload of its saved world. The release includes the latest-reported-count correction; both architecture slices retain macOS 13 as their minimum. No profile or world format migration is required.

A follow-up regression covers disconnect counts of 0, 1, 10, 2, and 0 across incremental refresh, unrelated log messages, and manager relaunch. Every valid count is retained until a newer count replaces it.

## Development preview 1.2.0 — management and scheduled restarts

Local validation on September 19, 2026; not a published release.

- 84 automated tests pass. Coverage includes local-calendar daily/interval/weekday schedules, DST gaps and repeated hours, midnight warning windows, missed occurrences, relaunch deduplication, changed-schedule claims, player policies/unknown counts, cancellation, warning failure, installation failure, per-server manual-stop precedence and maintenance locks.
- The full 900-second warning/restart workflow is exercised with a deterministic clock: warnings at 15/10/5/1, then Stop → Install → Start. No 10-second warning and no reset of the deadline.
- AppKit smoke checks exercise the actual status item through all update phases despite stale polled state, open/save/close the schedule editor, and open the performance/moderation window.
- Two isolated native ARM64 servers ran concurrently on Valheim 1.0.14 (build 25364309) and 1.0.15 (build 25390671). The source-built manager companion loaded on new worlds and saved worlds. Each server had a distinct localhost-only RCON port and private credential.
- Real RCON checks covered correct/incorrect authentication, unsupported commands, chat/center-screen warning RPCs, version/players/FPS/memory/uptime responses, synthetic-ID ban/unban with persisted profile values, and a kick request. No actual player was kicked or banned during these tests.
- On 1.0.15 the actual scheduled-restart window ran against an isolated crossplay server using a three-second test deadline and a development-only process launcher instead of launchd. It confirmed clean world save, stop, online startup, current join code and a scheduled maintenance-log entry. The second server retained its process ID. No public server or production launch agent was changed.
- A real SteamCMD update of the isolated 1.0.14 deployment completed, preserving every saved-world/config byte before startup. Both existing worlds then reloaded on 1.0.15 with management enabled and previous runtimes retained. The test waits for both game readiness and management readiness.
- The signed Intel app slice and management package also passed the two-server lifecycle/RCON checks under Rosetta on Apple Silicon. This is not physical Intel hardware validation.
- Package tests cover checksums before mutation, stable credentials/custom configuration, removal of obsolete managed DLLs, restoration of the previous runtime and blocking the rejected package/build. Recovery to vanilla hosting is available through Disable Server Management while stopped.
- The final ZIP was extracted independently; its app launched against fresh isolated data, all management manifest hashes matched, and its signature, stapled ticket and Gatekeeper assessment passed.
- The local universal app is Developer ID signed and notarized, including its native loader. The package contains third-party notices and the corresponding Doorstop source. Both architecture slices retain a macOS 13 minimum.

Coverage limits: physical Intel hardware, macOS 13 hardware, a full multi-server login/reboot cycle, and a populated-server restart with human observers have not been repeated for this preview. Warning timing is proven with a simulated clock; the live UI test intentionally shortens its deadline. The new companion's warning RPCs were exercised on empty test servers; earlier user-observed chat/center-screen verification used the prototype RCON plugin. General mod activation remains on its separate development branch and is not included here.

### Local 1.2.0 preview 2 — management window

- The isolated AppKit smoke test exercises the real management window: immediate checked/unchecked automatic-update feedback and persisted values, management tools on/off, schedule saving inside the Automation tab, disabled offline moderation, and the reduced server submenu.
- Scheduled-restart and automatic-update policy tests: 10 passed. Existing menu-bar transition and schedule-editor smoke checks also passed.
- All UI tests use a temporary `VSM_HOME`; no production server is started, stopped, or reconfigured.
- The automatic-update explanation now identifies the official Valheim dedicated server and uses separate tooltip paragraphs. Manual Refresh Status was removed; polling remains automatic.

- Performance smoke checks cover one-hour retention, server isolation, sampling with management windows closed, reopening history, stale reading expiry, and gaps across restarts.

## Release 1.2.4

Validation on September 26, 2026:

- 85 automated tests passed, including stopped-only default management installation, service-lock exclusion, explicit opt-out preservation, failed-install retry, unchanged world bytes/settings, and migration before a legacy server starts.
- AppKit checks passed for one-hour per-server retention, independent one-second collection with windows closed, reopening history, stale readings, restart gaps, management tabs, moderation selection, message availability and immediate automatic-update checkmarks.
- Two isolated native worlds tested the signed release app on Valheim 1.0.15. One profile deliberately had no management preference, matching an older deployment; its tools were installed automatically before startup. The other used the new-server default.
- Native tests cover distinct localhost-only endpoints, correct/incorrect authentication, empty player/banned lists, warning RPCs, live metrics, persisted synthetic ban/unban, clean save/restart, stable credentials and the second server remaining online with its original PID. Test worlds are disposable; production servers are not used.
- The native check caught collection fields missing from Unity's serialization of plugin data. The companion now uses managed JSON serialization; the checks passed with the corrected package.
- The universal release is Developer ID signed and Apple-notarized. Signature, Gatekeeper and package-manifest checks are performed on a separately extracted ZIP before publication.

The hardware and human-observed warning limitations above still apply. Chart history is session-local, not a persistent audit log. General community mod browsing/import remains excluded.
