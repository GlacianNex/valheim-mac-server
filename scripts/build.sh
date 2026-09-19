#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${VERSION:-1.2.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be major.minor.patch' >&2; exit 1; }
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then scripts/apple-preflight.sh; fi
export MACOSX_DEPLOYMENT_TARGET=13.0
swift build -c release --arch arm64 --arch x86_64
binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app="dist/Valheim Server Manager for Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/AppIcon.iconset
[[ -f dist/Management/manifest.json ]] || scripts/build-management.sh
rm -rf "$app/Contents/Resources/Management"
cp -R dist/Management "$app/Contents/Resources/Management"
cp "$binary_dir/ValheimServerMonitor" "$app/Contents/MacOS/ValheimServerMonitor"
swift scripts/make-icon.swift dist/AppIcon.png
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" dist/AppIcon.png --out "dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" dist/AppIcon.png --out "dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.glaciannex.valheimservermonitor</string>
<key>CFBundleName</key><string>Valheim Server Manager for Mac</string>
<key>CFBundleDisplayName</key><string>Valheim Server Manager for Mac</string>
<key>CFBundleExecutable</key><string>ValheimServerMonitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign the native loader before hashing the packaged files and signing the app.
loader="$app/Contents/Resources/Management/libdoorstop.dylib"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$loader"
else
    codesign --force --sign - "$loader"
fi
python3 - "$app/Contents/Resources/Management" <<'PYMANIFEST'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]); path=root/'manifest.json'; manifest=json.loads(path.read_text())
manifest['files']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in manifest['files']}
path.write_text(json.dumps(manifest,indent=2))
PYMANIFEST
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" dist/Valheim-Server-Manager-for-Mac.zip
(cd dist && shasum -a 256 Valheim-Server-Manager-for-Mac.zip > SHA256SUMS.txt)
printf 'Built %s\n' "$app"
