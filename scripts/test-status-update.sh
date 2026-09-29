#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/vsm-status-build.XXXXXX")
preview_pid=""
cleanup() {
  if [[ -n "$preview_pid" ]]; then
    kill "$preview_pid" 2>/dev/null || true
    wait "$preview_pid" 2>/dev/null || true
  fi
  if [[ -f /tmp/vsm-management-preview-path ]] && [[ "$(cat /tmp/vsm-management-preview-path)" == "$TEST_BUILD/Management Preview.app" ]]; then
    rm -f /tmp/vsm-management-preview-path
  fi
  rm -rf "$TEST_BUILD"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
swiftc -emit-library -emit-module -module-name ServerCore Sources/ServerCore/*.swift \
  -emit-module-path "$TEST_BUILD/ServerCore.swiftmodule" -o "$TEST_BUILD/libServerCore.dylib"
# Compile the real delegate without the production entry point (which starts services).
sed '/^umask(0o077)/,$d' Sources/ValheimServerMonitor/main.swift > "$TEST_BUILD/AppDelegate.swift"
UI_SOURCES=()
for file in Sources/ValheimServerMonitor/*.swift; do
  [[ "$file" == */main.swift ]] || UI_SOURCES+=("$file")
done
swiftc -parse-as-library -I "$TEST_BUILD" -L "$TEST_BUILD" -lServerCore \
  -Xlinker -rpath -Xlinker "$TEST_BUILD" "${UI_SOURCES[@]}" "$TEST_BUILD/AppDelegate.swift" scripts/status-update-smoke.swift \
  -o "$TEST_BUILD/status-update-smoke"
if [[ "${VSM_TEST_EXPERIMENTAL:-}" == "1" || ( "${VSM_UI_PREVIEW:-}" == "1" && -z "${VSM_UI_PREVIEW_IMAGE:-}" ) ]]; then
  PREVIEW_APP="$TEST_BUILD/Management Preview.app"
  mkdir -p "$PREVIEW_APP/Contents/MacOS"
  cp "$TEST_BUILD/status-update-smoke" "$PREVIEW_APP/Contents/MacOS/ManagementPreview"
  cat > "$PREVIEW_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.vsm.management-preview</string><key>CFBundleName</key><string>Management Preview</string><key>CFBundleExecutable</key><string>ManagementPreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
  if [[ "${VSM_TEST_EXPERIMENTAL:-}" == "1" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :VSMReleaseChannel string experimental' "$PREVIEW_APP/Contents/Info.plist"
  fi
  echo "$PREVIEW_APP" > /tmp/vsm-management-preview-path
  VSM_HOME="$TEST_BUILD/data" "$PREVIEW_APP/Contents/MacOS/ManagementPreview" &
  preview_pid=$!
  wait "$preview_pid"
else
  VSM_HOME="$TEST_BUILD/data" "$TEST_BUILD/status-update-smoke" &
  preview_pid=$!
  wait "$preview_pid"
fi
