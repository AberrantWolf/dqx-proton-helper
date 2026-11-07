#!/usr/bin/env bash
#
# Create the small user-facing release zip.
#
# This is the archive normal users should download from the GitHub "Latest"
# release. It contains the runtime scripts and concise docs needed to install
# and play, plus the current CrossOver delta pack.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

: "${RELEASE_NAME:=dqx-wine-helper-$(date +%Y%m%d)}"
: "${RELEASE_OUTPUT:=$REPO_DIR/build/release}"
CX_PATCH_BINPACK=dqx-wine-helper-macos-crossover-26.3-patches-v20261107.zip

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
msg() { printf '>> %s\n' "$*"; }

command -v zip >/dev/null 2>&1 || die "zip not found"
[ -f "$REPO_DIR/build/binpack-release/$CX_PATCH_BINPACK" ] \
  || die "Build the CrossOver patch pack first. See patches/crossover-26.3/README.md."

mkdir -p "$RELEASE_OUTPUT"
work="$(mktemp -d "${TMPDIR:-/tmp}/dqx-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/$RELEASE_NAME/platform"

copy_file() {
  local src="$1" dest="${2:-$1}"
  mkdir -p "$work/$RELEASE_NAME/$(dirname "$dest")"
  cp -p "$REPO_DIR/$src" "$work/$RELEASE_NAME/$dest"
}

copy_file dqx.sh
copy_file macos-crossover.sh
copy_file macos-fix-dqx-fonts.sh
copy_file platform/linux.sh
copy_file platform/macos-crossover.sh
copy_file platform/binpack.sh
copy_file platform/README.md
copy_file README.md
copy_file MACOS.md
copy_file UI-SCALING.md
copy_file MOVIES.md
copy_file LICENSES.md
copy_file UNLICENSE
copy_file patches/crossover-26.3/README.md
copy_file patches/crossover-26.3/artifacts/README.md
copy_file patches/crossover-26.2/source/winegstreamer-wma-dwstatus.patch
copy_file "build/binpack-release/$CX_PATCH_BINPACK" "$CX_PATCH_BINPACK"

cat >"$work/$RELEASE_NAME/QUICKSTART.md" <<'EOF'
# DQX Wine Helper Quickstart

This archive contains the helper scripts and the CrossOver movie patch deltas.
Install the game, Wine or CrossOver, and GStreamer separately.

Allow at least 48 GB of free disk space for DQX. Updates can temporarily need
more space.
[Official Windows requirements](https://hiroba.dqx.jp/sc/public/playguide/guide_1_1_win)

## Linux

```sh
./dqx.sh doctor
./dqx.sh fetch-binpack
./dqx.sh setup
./dqx.sh install /path/to/Setup.exe
./dqx.sh play
```

## macOS / CrossOver

Install **CrossOver 26.3 build `26.3.0.39832`** and the official universal macOS
GStreamer framework. The movie fixes were verified with GStreamer 1.28.4.
Quit CrossOver and its Windows programs before running setup.

```sh
./dqx.sh fetch-binpack
./dqx.sh setup
./dqx.sh doctor
./dqx.sh install /path/to/Setup.exe
./dqx.sh play
```

`fetch-binpack` downloads the pinned Win32 helper pack and, on macOS, verifies
and installs the CrossOver 26.3 movie delta pack included in this archive.

See `README.md` for the full Linux path and `MACOS.md` for the current
CrossOver-specific notes.
EOF

manifest="$work/$RELEASE_NAME/manifest.json"
{
  printf '{\n'
  printf '  "name": "%s",\n' "$RELEASE_NAME"
  printf '  "format": 1,\n'
  printf '  "kind": "user-scripts",\n'
  printf '  "files": [\n'
  first=1
  while IFS= read -r -d '' file; do
    rel="${file#$work/$RELEASE_NAME/}"
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
    size="$(wc -c <"$file" | tr -d ' ')"
    if [ "$rel" = "manifest.json" ]; then
      continue
    fi
    if [ "$first" = 0 ]; then printf ',\n'; fi
    first=0
    printf '    {"path": "%s", "sha256": "%s", "size": %s}' "$rel" "$hash" "$size"
  done < <(find "$work/$RELEASE_NAME" -type f -print0 | sort -z)
  printf '\n'
  printf '  ]\n'
  printf '}\n'
} >"$manifest"

zip_path="$RELEASE_OUTPUT/$RELEASE_NAME.zip"
(
  cd "$work"
  zip -qr "$zip_path" "$RELEASE_NAME"
)

msg "Wrote $zip_path"
msg "SHA-256:"
shasum -a 256 "$zip_path"
