# Seed support (1.1.2)

New Server has an optional case-sensitive seed of 1–10 ASCII letters or digits. Blank means Valheim generates a random seed. A seed request applies only while allocating a brand-new profile/world directory. Existing profiles cannot change it, even before their first start. Imports reject seed overrides and display their existing seed read-only.

The manager creates an ungenerated legacy `.fwl` (metadata version 35) with world-generation version 2, a fresh UID, the case-sensitive seed string and its stable 32-bit hash, `needsDB=false`, and no initial global keys. Valheim generates the world and upgrades it to its current chunked save format. It never fabricates a `.db` or edits an existing world's terrain.

This is a save-format integration, not a documented command-line flag. It was checked against the native dedicated server Steam build 25253791: its World constructor selects world-generation version 2, its metadata loader accepts the legacy format, and its string hash uses two alternating 32-bit accumulators. No game binary or decompiled source is included in the repository. The app adds no runtime dependency.

## Verification

- 50 Swift tests pass, including creation, validation, old-profile decoding, import preservation, immutable seed requests, long UTF-8 world filenames, and hash comparison against a native-server-generated disposable world.
- Two native start/save/stop/restart cycles passed for Meadows42, retaining the requested seed and world-generation version 2.
- The signed 1.1.0 app repeated those cycles using the seed from a previously server-generated random fixture. Its resulting 20,971,532-byte biome cache was byte-for-byte identical to that original fixture. The different seed produced a different biome cache.
- UI creation was exercised in an isolated VSM_HOME. The entered seed was saved and read back from world metadata.
- Apple notarization, ticket stapling, and Gatekeeper assessment passed. The maintainer confirmed the combined 1.1.2 build worked before approving publication.

The game can change generation rules or save formats in future updates. Re-run native integration when these change; do not substitute an older generation version merely because an old metadata example uses it. This implementation does not claim that identical seeds produce identical terrain across different game-generation versions.

To repeat seeded lifecycle validation with a disposable, previously nonexistent root:

```sh
python3 scripts/integration.py --binary 'dist/Valheim Server Manager for Mac.app/Contents/MacOS/ValheimServerMonitor' --root /path/to/new-test-root --runtime /path/to/test-runtime --port 29830 --seed Meadows42
```

Use an isolated test runtime and unused UDP port pair. The script never registers launch agents. The default integration test without `--seed` still exercises random creation.
