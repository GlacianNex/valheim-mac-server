# Releasing

The release ZIP contains the monitor only. SteamCMD and Valheim are downloaded separately from Valve during setup.

## Local build

```sh
swift test
VERSION=0.1.0 scripts/build.sh
```

Without `SIGNING_IDENTITY`, this creates an ad-hoc-signed preview. Do not describe it as notarized or Gatekeeper-ready.

For a public notarized build, use an Apple Developer Program account with a **Developer ID Application** certificate. An **Apple Development** certificate is not a substitute.

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' VERSION=0.1.0 scripts/build.sh
xcrun notarytool submit dist/Valheim-Server-Monitor.zip --keychain-profile VSM_NOTARY --wait
xcrun stapler staple 'dist/Valheim Server Monitor.app'
xcrun stapler validate 'dist/Valheim Server Monitor.app'
spctl --assess --type execute --verbose=2 'dist/Valheim Server Monitor.app'
ditto -c -k --keepParent 'dist/Valheim Server Monitor.app' dist/Valheim-Server-Monitor.zip
(cd dist && shasum -a 256 Valheim-Server-Monitor.zip > SHA256SUMS.txt)
```

Create the `VSM_NOTARY` credential profile with Apple's `notarytool store-credentials` on your own machine. Never put the password, API key, certificate, or private key in source control.

## GitHub workflow

The manual Release workflow accepts a version and whether signing is enabled. It creates a **draft prerelease** for review. For signing/notarization configure repository secrets:

- `APPLE_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate and private key.
- `APPLE_CERTIFICATE_PASSWORD`: export password.
- `APPLE_SIGNING_IDENTITY`: full Developer ID Application identity.
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`: notarization credentials.

The unsigned workflow is useful for previews. Before making a stable release, verify a clean download on another Mac, first-run setup, player connectivity, safe shutdown and reload, and login startup. Publish the reviewed release only after the signing/notarization gates have passed.
