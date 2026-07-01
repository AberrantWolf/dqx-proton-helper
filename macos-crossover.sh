#!/usr/bin/env bash
#
# Compatibility wrapper. Prefer ./dqx.sh; this file keeps older notes and local
# muscle memory working while the macOS CrossOver implementation lives in
# platform/macos-crossover.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
exec "$SCRIPT_DIR/dqx.sh" --platform macos-crossover "$@"
