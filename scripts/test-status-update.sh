#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/vsm-status-build.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
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
VSM_HOME="$TEST_BUILD/data" "$TEST_BUILD/status-update-smoke"
