# Apple signing and notarization

This project distributes directly from GitHub using **Developer ID Application signing and Apple notarization**. This is not Mac App Store review or a certification of code quality. Apple checks the submitted app for malicious content and signing problems, then issues a ticket that Gatekeeper can verify.

## Distribution requirements

- The universal app builds for macOS 13+, Apple Silicon and Intel.
- Signed builds enable hardened runtime and secure timestamps. The Swift manager needs no JIT, unsigned-library, debugger, or App Sandbox exception entitlements. Valve's tools/server are separate downloaded processes, not bundled plug-ins.
- `scripts/apple-preflight.sh` checks distribution identity availability before a signed build.
- `scripts/notarize.sh` validates the signed bundle, submits the exact archive, requires Apple's Accepted status, staples and validates the ticket, runs Gatekeeper assessment, and recreates the ZIP/checksum afterward.
- The GitHub release workflow uses that same script and saves notarization diagnostics on failure.


## Account steps for the maintainer

1. [Enroll in the Apple Developer Program](https://developer.apple.com/programs/enroll/). Complete identity verification and Apple's agreements yourself. Choose individual or organization according to who will distribute the app; do not enroll as a company you do not represent.
2. After approval, use Xcode's account certificate management or [Apple's certificate portal](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) to create **Developer ID Application**. Keep its private key on your Mac. A Developer ID Installer certificate is only needed if we later ship a signed `.pkg`; it is not needed for this `.app` in a ZIP.
3. Verify the identity is available using `security find-identity -v -p codesigning`. Its name should begin `Developer ID Application:`. Preserve the existing bundle identifier `io.github.glaciannex.valheimservermonitor`; the product rename does not require a new identifier.
4. Create an app-specific password for your Apple Account and save it through the interactive Keychain command below. Enter secrets locally, not into chat, source files, or shell history. `notarytool` validates the credentials with Apple.

```sh
xcrun notarytool store-credentials VSM_NOTARY
```

Use the Team ID associated with the Developer Program membership. No Apple credentials need to be stored on GitHub for local notarized releases.

## Notarized build

Use a new version number so the updater recognizes it as newer. Never replace an existing release archive with a different build.

```sh
export SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
scripts/apple-preflight.sh
swift test
VERSION=1.0.0 scripts/build.sh
NOTARY_PROFILE=VSM_NOTARY scripts/notarize.sh
```

The output is `dist/Valhiem-Server-Manager-for-Mac.zip` plus `dist/SHA256SUMS.txt`. Submission status, ID, and available Apple logs are in `dist/notarization/`. None of these commands start or modify an installed game server.

If Apple returns Invalid, inspect its log and fix the reported paths. If processing times out, Apple continues processing: retrieve the saved submission ID and use `notarytool info` or `notarytool wait` with the same Keychain profile. Once accepted, staple, validate, assess, and repackage as described in [RELEASING.md](RELEASING.md). Never label a release notarized based only on upload success.

## Verification before publication

Download the proposed signed ZIP through a browser on another Mac so quarantine is present. Do not remove quarantine or approve Open Anyway during this test. Verify:

- Gatekeeper accepts the download with the ordinary first-open confirmation, without an unidentified-developer override.
- Copy to Applications, quit/reopen, and update from the older public app work.
- In a disposable world, native installation, version checking, server start, graceful save/stop/reload, and server-update restart work under the signed manager.
- Login startup uses the existing stable paths and preferences.
- `codesign --verify --deep --strict`, `stapler validate`, and `spctl --assess --type execute` pass on the final bundle extracted from the downloadable ZIP.

Hardened-runtime smoke tests and automated CI cannot replace this browser-download test. Do not use an existing live world to qualify the release.

## Optional GitHub signing

After the local release works, configure the secrets listed in [RELEASING.md](RELEASING.md). Export only the Developer ID Application certificate with its private key into an encrypted P12; upload it as a repository secret, never commit it. The workflow creates a temporary runner keychain and removes it afterward. Keep signing restricted to the maintainer-triggered release workflow. Do not give signing secrets to pull-request builds.

## Apple references

- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing notarization, logs, and credentials](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
