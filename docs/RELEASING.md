# Releasing

The ZIP contains the manager only. SteamCMD and Valheim are downloaded from Valve during setup.

## Build and notarize locally

Use a new version number, update the build default and changelog, and run:

```sh
swift test
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' VERSION=1.0.0 scripts/build.sh
NOTARY_PROFILE=VSM_NOTARY scripts/notarize.sh
```

See [Apple distribution](APPLE-DISTRIBUTION.md) for certificate and Keychain setup. Without SIGNING_IDENTITY, builds are ad-hoc signed development artifacts and are not notarized.

The notarization script validates the signed bundle, submits the archive, requires Apple's Accepted status, staples and validates the ticket, assesses Gatekeeper, and recreates the ZIP/checksum. Diagnostics are in `dist/notarization/`. For a timeout, inspect the saved submission ID with notarytool info/wait instead of resubmitting immediately.

Extract the final ZIP into a separate directory and verify its signature, stapled ticket, and Gatekeeper assessment. Run the checks appropriate to the change, record meaningful coverage limits in [verification](VERIFICATION.md), and test installation/update from a downloaded artifact. Do not use a live world for development testing.

Commit the release sources and documentation, wait for CI, then create the GitHub release against that commit with `dist/Valheim-Server-Manager-for-Mac.zip` and `dist/SHA256SUMS.txt`. Publish a regular release as latest when approved. Never silently replace an existing release’s binary with different contents.

## GitHub workflow

The manual Prepare release workflow builds and creates a draft. Signed drafts require these repository secrets:

- APPLE_CERTIFICATE_P12 — base64-encoded Developer ID certificate with private key.
- APPLE_CERTIFICATE_PASSWORD — export password.
- APPLE_SIGNING_IDENTITY — full Developer ID Application identity.
- APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD — notarization credentials.

The workflow uses a temporary keychain and removes signing material afterward. Unsigned drafts are development prereleases. The ordinary CI artifact is also an unnotarized development build, not the public download. Never put signing credentials or world data in source control.
