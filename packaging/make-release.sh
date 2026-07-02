#!/usr/bin/env bash
#
# Create the small user-facing release zip.
#
# This is the archive normal users should download from the GitHub "Latest"
# release. It contains the runtime scripts and concise docs needed to install
# and play, but not research notes, diagnostic source, or CrossOver source
# patches.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

: "${RELEASE_NAME:=dqx-wine-helper-$(date +%Y%m%d)}"
: "${RELEASE_OUTPUT:=$REPO_DIR/build/release}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
msg() { printf '>> %s\n' "$*"; }

command -v zip >/dev/null 2>&1 || die "zip not found"

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
copy_file platform/README.md
copy_file README.md
copy_file MACOS.md
copy_file UI-SCALING.md
copy_file MOVIES.md
copy_file LICENSES.md
copy_file UNLICENSE

cat >"$work/$RELEASE_NAME/QUICKSTART.md" <<'EOF'
# DQX Wine Helper Quickstart

This is the small user-facing release archive. It does not include the game,
CrossOver, Wine, GStreamer, or generated binary helper packs.

## Linux

```sh
./dqx.sh doctor
./dqx.sh fetch-binpack
./dqx.sh setup
./dqx.sh install /path/to/Setup.exe
./dqx.sh play
```

## macOS / CrossOver

Install CrossOver and the official macOS GStreamer framework first, then:

```sh
./dqx.sh doctor
./dqx.sh fetch-binpack
./dqx.sh setup
./dqx.sh install /path/to/Setup.exe
./dqx.sh play
```

`fetch-binpack` downloads pinned release assets for the small Win32 helper
executables and, on macOS/CrossOver, the CrossOver 26.2 binary deltas.

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
