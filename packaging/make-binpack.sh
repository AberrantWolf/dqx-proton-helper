#!/usr/bin/env bash
#
# Create a source-repo-external binary pack for GitHub Releases.
#
# Input files are copied from build/binpack-input/ and preserved with the same
# relative paths inside the zip. Keep full CodeWeavers modules out of this pack.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

: "${BINPACK_NAME:=dqx-wine-helper-macos-crossover-26.2-binpack-$(date +%Y%m%d)}"
: "${BINPACK_INPUT:=$REPO_DIR/build/binpack-input}"
: "${BINPACK_OUTPUT:=$REPO_DIR/build/binpack-release}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
msg() { printf '>> %s\n' "$*"; }

[ -d "$BINPACK_INPUT" ] || die "input directory not found: $BINPACK_INPUT"
command -v zip >/dev/null 2>&1 || die "zip not found"

mkdir -p "$BINPACK_OUTPUT"
work="$(mktemp -d "${TMPDIR:-/tmp}/dqx-binpack.XXXXXX")"
trap 'rm -rf "$work"' EXIT

rsync -a --exclude '.DS_Store' "$BINPACK_INPUT"/ "$work"/

if find "$work" -type f \( -name 'win32u.so' -o -name 'winegstreamer.dll' -o -name 'winegstreamer.so' \) | grep -q .; then
  die "refusing to package full CrossOver modules; use .bsdiff deltas instead"
fi

manifest="$work/manifest.json"
{
  printf '{\n'
  printf '  "name": "%s",\n' "$BINPACK_NAME"
  printf '  "format": 1,\n'
  printf '  "target": {\n'
  printf '    "platform": "macos",\n'
  printf '    "crossover": "26.2"\n'
  printf '  },\n'
  printf '  "files": [\n'
  first=1
  while IFS= read -r -d '' file; do
    rel="${file#$work/}"
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
    size="$(wc -c <"$file" | tr -d ' ')"
    if [ "$rel" = "manifest.json" ]; then
      continue
    fi
    if [ "$first" = 0 ]; then
      printf ',\n'
    fi
    first=0
    printf '    {"path": "%s", "sha256": "%s", "size": %s}' "$rel" "$hash" "$size"
  done < <(find "$work" -type f -print0 | sort -z)
  printf '\n'
  printf '  ]\n'
  printf '}\n'
} >"$manifest"

zip_path="$BINPACK_OUTPUT/$BINPACK_NAME.zip"
(
  cd "$work"
  zip -qr "$zip_path" .
)

msg "Wrote $zip_path"
msg "SHA-256:"
shasum -a 256 "$zip_path"
