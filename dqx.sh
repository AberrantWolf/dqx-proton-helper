#!/usr/bin/env bash
#
# dqx.sh - Dragon Quest X Online helper dispatcher.
#
# One user-facing entrypoint, with platform-specific implementations kept under
# platform/. The default platform is detected from the host OS; override with
# DQX_PLATFORM=linux or DQX_PLATFORM=macos-crossover, or pass
# --platform <name> before the command.
#
# Usage:
#   ./dqx.sh [--platform linux|macos-crossover] doctor
#   ./dqx.sh [--platform linux|macos-crossover] setup
#   ./dqx.sh [--platform linux|macos-crossover] install /path/to/Setup.exe
#   ./dqx.sh [--platform linux|macos-crossover] play

set -euo pipefail

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

msg()  { printf '\033[1;36m>>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d; s/^# \{0,1\}//'
  cat <<'EOF'

Platform selection:
  auto             Detect from this host (default)
  linux            Plain Wine on Linux
  macos-crossover  CrossOver on Apple Silicon macOS

Examples:
  ./dqx.sh doctor
  ./dqx.sh setup
  ./dqx.sh install /path/to/Setup.exe
  ./dqx.sh play
  ./dqx.sh --platform macos-crossover fetch-binpack
EOF
}

normalize_platform() {
  case "$1" in
    ""|auto) printf 'auto\n' ;;
    linux) printf 'linux\n' ;;
    mac|macos|crossover|macos-crossover) printf 'macos-crossover\n' ;;
    *) die "Unknown DQX platform '$1' (expected auto, linux, or macos-crossover)" ;;
  esac
}

detect_platform() {
  local requested
  requested="$(normalize_platform "${DQX_PLATFORM:-auto}")"
  if [ "$requested" != auto ]; then
    printf '%s\n' "$requested"
    return 0
  fi

  case "$(uname -s)" in
    Linux) printf 'linux\n' ;;
    Darwin)
      if [ -d "${CX_APP:-/Applications/CrossOver.app}" ]; then
        printf 'macos-crossover\n'
      else
        die "macOS detected, but CrossOver was not found. Set CX_APP or DQX_PLATFORM."
      fi
      ;;
    *) die "Unsupported OS: $(uname -s). Set DQX_PLATFORM if you know what you are doing." ;;
  esac
}

platform="${DQX_PLATFORM:-auto}"
if [ "${1:-}" = "--platform" ]; then
  [ -n "${2:-}" ] || die "Usage: ./dqx.sh --platform linux|macos-crossover <command>"
  platform="$2"
  shift 2
elif [[ "${1:-}" == --platform=* ]]; then
  platform="${1#--platform=}"
  shift
fi

case "${1:-}" in
  ""|-h|--help|help)
    usage
    exit 0
    ;;
esac

platform="$(DQX_PLATFORM="$platform" detect_platform)"
case "$platform" in
  linux) module="$REPO_DIR/platform/linux.sh" ;;
  macos-crossover) module="$REPO_DIR/platform/macos-crossover.sh" ;;
  *) die "No module for platform '$platform'" ;;
esac

[ -x "$module" ] || die "Platform module is missing or not executable: $module"
msg "Using platform: $platform"
export DQX_PLATFORM="$platform"
export DQX_REPO_DIR="$REPO_DIR"
exec "$module" "$@"
