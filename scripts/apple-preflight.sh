#!/bin/bash
set -euo pipefail
# Read-only check. No certificate export, account changes, or server operations.
for tool in codesign security ditto shasum; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
identities="$(security find-identity -v -p codesigning)"
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    echo 'Set SIGNING_IDENTITY to your full Developer ID Application certificate name.' >&2
    if [[ "$identities" != *'Developer ID Application:'* ]]; then
        echo 'No valid Developer ID Application identity is installed. Create one in Xcode or your Apple Developer account first.' >&2
    fi
    exit 1
fi
[[ "$SIGNING_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'An Apple Development certificate cannot sign a public notarized release.' >&2; exit 1; }
[[ "$identities" == *"\"$SIGNING_IDENTITY\""* ]] || { echo 'The selected identity and its private key are not available in the current keychain.' >&2; exit 1; }
echo 'Developer ID identity and Apple notarization tools are available.'
echo 'Notarization credentials are validated separately; nothing has been submitted.'
