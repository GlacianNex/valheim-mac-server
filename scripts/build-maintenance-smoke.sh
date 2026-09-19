#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VSM_TEST_UI_BUILD:?Set an isolated test build output directory}"
mkdir -p "$VSM_TEST_UI_BUILD"
swiftc -emit-library -emit-module -module-name ServerCore Sources/ServerCore/*.swift -emit-module-path "$VSM_TEST_UI_BUILD/ServerCore.swiftmodule" -o "$VSM_TEST_UI_BUILD/libServerCore.dylib"
swiftc -parse-as-library -I "$VSM_TEST_UI_BUILD" -L "$VSM_TEST_UI_BUILD" -lServerCore -Xlinker -rpath -Xlinker "$VSM_TEST_UI_BUILD" Sources/ValheimServerMonitor/ServerUpdate.swift scripts/maintenance-window-smoke.swift -o "$VSM_TEST_UI_BUILD/maintenance-window-smoke"
