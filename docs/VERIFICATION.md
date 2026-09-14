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
