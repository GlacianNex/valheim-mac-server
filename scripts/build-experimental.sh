#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_CHANNEL=experimental bash scripts/build.sh
