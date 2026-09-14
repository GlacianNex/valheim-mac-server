#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app='dist/Valhiem Server Manager for Mac.app'
archive='dist/Valhiem-Server-Manager-for-Mac.zip'
mkdir -p dist/notarization
codesign --verify --deep --strict "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$signature" == *'Authority=Developer ID Application:'* ]] || { echo 'Refusing notarization: build with Developer ID Application signing first.' >&2; exit 1; }
[[ "$signature" == *'runtime'* && "$signature" == *'Timestamp='* ]] || { echo 'Signed build must enable hardened runtime and a secure timestamp.' >&2; exit 1; }
codesign -d --entitlements :- "$app" > dist/notarization/entitlements.plist 2>/dev/null
if [[ -s dist/notarization/entitlements.plist ]]; then
    debug=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' dist/notarization/entitlements.plist 2>/dev/null || true)
    [[ "$debug" != true ]] || { echo 'Refusing notarization: debug entitlement is enabled.' >&2; exit 1; }
fi
# Use a local Keychain profile by default. CI may supply app-specific credentials.
if [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    : "${APPLE_ID:?Set APPLE_ID}" "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
    credentials=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
else
    credentials=(--keychain-profile "${NOTARY_PROFILE:-VSM_NOTARY}")
fi
# Repack the exact signed bundle; never submit a stale ZIP from an earlier build.
ditto -c -k --keepParent "$app" "$archive"
submission='dist/notarization/submission.json'
submitted=true
xcrun notarytool submit "$archive" "${credentials[@]}" --wait --timeout 30m --output-format json > "$submission" || submitted=false
status=$(/usr/bin/plutil -extract status raw -o - "$submission" 2>/dev/null || true)
id=$(/usr/bin/plutil -extract id raw -o - "$submission" 2>/dev/null || true)
if [[ -n "$id" && ( "$status" == Accepted || "$status" == Invalid || "$status" == Rejected ) ]]; then
    xcrun notarytool log "$id" "${credentials[@]}" dist/notarization/apple-log.json || true
fi
if [[ "$submitted" != true || "$status" != Accepted ]]; then
    echo "Apple has not confirmed acceptance. Inspect $submission and any apple-log.json. Do not publish as notarized." >&2
    echo 'If processing timed out, use notarytool info/wait with the saved submission ID; do not immediately resubmit.' >&2
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
# Stapling changes the bundle, so recreate the download and checksum afterward.
ditto -c -k --keepParent "$app" "$archive"
(cd dist && shasum -a 256 Valhiem-Server-Manager-for-Mac.zip > SHA256SUMS.txt)
echo 'Apple accepted the submission. Ticket stapled and Gatekeeper assessment passed.'
echo 'Test the browser-downloaded ZIP on another Mac before publishing.'
