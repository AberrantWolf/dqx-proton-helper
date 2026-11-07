#!/usr/bin/env bash
#
# platform/macos-crossover.sh - Dragon Quest X Online on Apple Silicon CrossOver.
#
# This helper targets the currently verified minimal CrossOver path:
#   - CrossOver 26.3 in /Applications/CrossOver.app
#   - a DQX bottle
#   - stock game install location
#   - downloaded IPAMona fonts + Ume UI Gothic font aliases
#   - GStreamer.framework for WMV/WMA codecs
#   - locally supplied CrossOver binary patches when needed
#   - optional helper binaries from an unpacked release binpack
#
# It does not download or provide the game, CrossOver, GStreamer, or patched
# CodeWeavers binaries. It can download the redistributable IPAMona font
# package from FreeBSD's ports distcache and install the TTFs for the user.
#
# Usage:
#   ./dqx.sh doctor
#   ./dqx.sh setup
#   ./dqx.sh fetch-binpack
#   ./dqx.sh binpack /path/to/binpack.zip
#   ./dqx.sh patches
#   ./dqx.sh fonts
#   ./dqx.sh install /path/to/Setup.exe
#   ./dqx.sh play
#
# Config:
#   CX_APP        CrossOver app bundle       (default: /Applications/CrossOver.app)
#   CX_BOTTLE     CrossOver bottle name      (default: DQX)
#   DQX_PATCH_DIR Local patch artifact dir   (default: ./patches/crossover-26.3/artifacts)
#   DQX_WIN32_BINPACK  Unpacked win32 helper binpack (default: ./vendor/binpack/win32)
#   DQX_CX_PATCH_BINPACK  Unpacked CrossOver patch binpack (default: ./vendor/binpack/macos-crossover-26.3)
#   DQX_BINPACK_SHA256  Optional expected SHA-256 for ./dqx.sh binpack
#   DQX_INHIBIT   1=hold a caffeinate lock   (default: 1)

set -euo pipefail

: "${CX_APP:=/Applications/CrossOver.app}"
: "${CX_BOTTLE:=DQX}"
: "${DQX_INHIBIT:=1}"
CX_SUPPORTED_BUILD=26.3.0.39832

PLATFORM_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
: "${DQX_REPO_DIR:=$(CDPATH= cd -- "$PLATFORM_DIR/.." && pwd -P)}"
SCRIPT_DIR="$DQX_REPO_DIR"
: "${DQX_PATCH_DIR:=$DQX_REPO_DIR/patches/crossover-26.3/artifacts}"
: "${DQX_WIN32_BINPACK:=${DQX_BINPACK:-$DQX_REPO_DIR/vendor/binpack/win32}}"
: "${DQX_CX_PATCH_BINPACK:=$DQX_REPO_DIR/vendor/binpack/macos-crossover-26.3}"

CX_ROOT="$CX_APP/Contents/SharedSupport/CrossOver"
CX_WINE="$CX_ROOT/bin/wine"
CX_BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$CX_BOTTLE"
CX_BOTTLE_CONF="$CX_BOTTLE_DIR/cxbottle.conf"

DQX_REL='drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X'
DQX_UNIX_DIR="$CX_BOTTLE_DIR/$DQX_REL"
DQX_BOOT_DIR="$DQX_UNIX_DIR/Boot"
DQX_GAME_WIN='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'

WIN32_BINPACK_RELEASE_TAG="win32-binpack-v20260701"
WIN32_BINPACK_DIST="dqx-wine-helper-win32-binpack-v20260701.zip"
WIN32_BINPACK_URL="https://github.com/AberrantWolf/dqx-proton-helper/releases/download/$WIN32_BINPACK_RELEASE_TAG/$WIN32_BINPACK_DIST"
WIN32_BINPACK_SHA256="4be18b4dbc0d4a3b07e8e0acc685cbb6cff0e06f8b67d5c814a6651e948358d3"

CX_PATCH_BINPACK_DIST="dqx-wine-helper-macos-crossover-26.3-patches-v20261107.zip"
CX_PATCH_BINPACK_SHA256="64722a1cbead7595e59ed1087ab1127f8507d211243f39016969a6437f5db98e"
BINPACK_CACHE_DIR="$HOME/Library/Caches/dqx-wine-helper/binpack"

GST_ROOT="/Library/Frameworks/GStreamer.framework/Versions/1.0"
GST_INSPECT="$GST_ROOT/bin/gst-inspect-1.0"
GST_PLUGIN_DIR="$GST_ROOT/lib/gstreamer-1.0"
GST_REGISTRY="$CX_BOTTLE_DIR/gstreamer-1.0-registry.x86_64.bin"

FONT_HELPER="$SCRIPT_DIR/macos-fix-dqx-fonts.sh"

IPAMONA_DIST="opfc-ModuleHP-1.1.1_withIPAMonaFonts-1.0.8.tar.gz"
IPAMONA_SHA256="ab77beea3b051abf606cd8cd3badf6cb24141ef145c60f508fcfef1e3852bb9d"
IPAMONA_CACHE_DIR="$HOME/Library/Caches/dqx-wine-helper/ipamona"
IPAMONA_CACHE_FILE="$IPAMONA_CACHE_DIR/$IPAMONA_DIST"
IPAMONA_URLS=(
  "http://distcache.FreeBSD.org/local-distfiles/hrs/$IPAMONA_DIST"
  "http://distcache.us-east.FreeBSD.org/local-distfiles/hrs/$IPAMONA_DIST"
  "http://distcache.eu.FreeBSD.org/local-distfiles/hrs/$IPAMONA_DIST"
  "http://distcache.us-west.FreeBSD.org/local-distfiles/hrs/$IPAMONA_DIST"
)
IPAMONA_FONT_FILES=(
  ipag-mona.ttf
  ipagp-mona.ttf
  ipagui-mona.ttf
  ipam-mona.ttf
  ipamp-mona.ttf
)

WINEGSTREAMER_PE_HASH='2d933d85622e5947394ccf31a78dee4d2ea349b40950ae40b097ddb61f9e3f24'
WINEGSTREAMER_UNIX_HASH='161ef102ec4d3cf045979119c60697cfa99d1b2fc54ef255c2f7024e5cda850a'

WINEGSTREAMER_PE_STOCK_HASH='763215f95c1e9eb955efdd2e3b5abeae29d5596232dc7baa828873cfe3ab23ec'
WINEGSTREAMER_UNIX_STOCK_HASH='1a1b12a5860447a3e9aa73d29c6a0686a0526c193cc863fd7cfab0a9eaa1c0d3'

WINEGSTREAMER_PE_TARGET="$CX_ROOT/lib/wine/i386-windows/winegstreamer.dll"
WINEGSTREAMER_UNIX_TARGET="$CX_ROOT/lib/wine/x86_64-unix/winegstreamer.so"
BOTTLE_WINEGSTREAMER_PE="$CX_BOTTLE_DIR/drive_c/windows/syswow64/winegstreamer.dll"

msg()  { printf '\033[1;36m>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

sha256_file() {
  [ -f "$1" ] || return 1
  shasum -a 256 "$1" | awk '{print $1}'
}

abs_existing_file() {
  [ -f "$1" ] || return 1
  (CDPATH= cd -- "$(dirname -- "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "$1")")
}

require_crossover() {
  [ -d "$CX_APP" ] || die "CrossOver app not found: $CX_APP"
  [ -x "$CX_WINE" ] || die "CrossOver wine wrapper not found: $CX_WINE"
}

check_crossover_build() {
  local build
  build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$CX_APP/Contents/Info.plist" 2>/dev/null)" \
    || build="unknown"
  if [ "$build" != "$CX_SUPPORTED_BUILD" ]; then
    warn "CrossOver build $build is unsupported. Use CrossOver 26.3 build $CX_SUPPORTED_BUILD (set CX_APP if needed)."
    return 1
  fi
}

cx() {
  require_crossover
  "$CX_WINE" --bottle "$CX_BOTTLE" "$@"
}

cx_workdir() {
  local workdir="$1"
  shift
  require_crossover
  "$CX_WINE" --bottle "$CX_BOTTLE" --workdir "$workdir" "$@"
}

launcher_clip_helper() {
  if [ -f "$DQX_WIN32_BINPACK/bin/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$DQX_WIN32_BINPACK/bin/dqx-launcher-clip.exe"
  elif [ -f "$SCRIPT_DIR/vendor/binpack/bin/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$SCRIPT_DIR/vendor/binpack/bin/dqx-launcher-clip.exe"
  elif [ -f "$SCRIPT_DIR/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$SCRIPT_DIR/dqx-launcher-clip.exe"
  else
    return 1
  fi
}

check_hash() {
  local label="$1" target="$2" expected="$3" actual
  if [ ! -f "$target" ]; then
    warn "$label: missing ($target)"
    return 1
  fi
  actual="$(sha256_file "$target")"
  if [ "$actual" = "$expected" ]; then
    ok "$label: patched hash present"
    return 0
  fi
  warn "$label: hash is not the verified patched build"
  warn "  actual:   $actual"
  warn "  expected: $expected"
  return 1
}

check_movie_patches() {
  local status=0
  check_hash "App WMA-DMO patch" "$WINEGSTREAMER_PE_TARGET" "$WINEGSTREAMER_PE_HASH" || status=1
  check_hash "App GStreamer framework bridge" "$WINEGSTREAMER_UNIX_TARGET" "$WINEGSTREAMER_UNIX_HASH" || status=1
  if [ -d "$CX_BOTTLE_DIR/drive_c" ]; then
    check_hash "Bottle WMA-DMO patch" "$BOTTLE_WINEGSTREAMER_PE" "$WINEGSTREAMER_PE_HASH" || status=1
  fi
  return "$status"
}

prepare_patch() {
  local target="$1" stock_hash="$2" expected="$3" output="$4"
  local module="${target##*/}" actual artifact delta
  artifact="$DQX_PATCH_DIR/$module"
  delta="$DQX_CX_PATCH_BINPACK/patches/crossover-26.3/binary-deltas/$module.bsdiff"

  actual="$(sha256_file "$target")" || die "CrossOver module missing or unreadable: $target"
  if [ "$actual" = "$expected" ]; then
    ok "$module: already patched"
    return 0
  fi
  [ "$actual" = "$stock_hash" ] \
    || die "$module: unexpected module hash $actual. Restore stock CrossOver 26.3 build $CX_SUPPORTED_BUILD."

  if [ -f "$artifact" ]; then
    cp -p "$artifact" "$output"
  else
    [ -f "$delta" ] || die "$module: no patch available. Run './dqx.sh fetch-binpack'."
    command -v bspatch >/dev/null 2>&1 || die "bspatch not found; cannot apply the $module delta"
    bspatch "$target" "$output" "$delta" || die "$module: could not apply the binpack delta"
  fi
  actual="$(sha256_file "$output")"
  [ "$actual" = "$expected" ] || die "$module: prepared patch hash mismatch ($actual)"
  if [ "$module" = winegstreamer.so ]; then
    codesign --verify "$output" || die "$module: invalid local code signature"
  fi
}

install_patch() (
  local target="$1" stock_hash="$2" expected="$3" source="$4" actual backup staged
  [ -f "$source" ] || return 0
  actual="$(sha256_file "$target")" || die "CrossOver module missing or unreadable: $target"
  [ "$actual" != "$expected" ] || return 0
  [ "$actual" = "$stock_hash" ] || die "CrossOver module changed during setup: $target"
  staged="$(mktemp "$target.dqx-patch.XXXXXX")"
  trap 'rm -f "$staged"' EXIT
  cp -p "$target" "$staged"
  cat "$source" >"$staged"
  backup="$(mktemp "$target.stock-before-dqx-$(date +%Y%m%d-%H%M%S).XXXXXX")"
  cp -p "$target" "$backup"
  msg "Backed up ${target##*/} to ${backup##*/}"
  mv -f "$staged" "$target"
  check_hash "${target##*/}" "$target" "$expected"
)

have_ipamona_fonts() {
  local font
  for font in "${IPAMONA_FONT_FILES[@]}"; do
    [ -f "$HOME/Library/Fonts/$font" ] || return 1
  done
}

download_ipamona_package() {
  local url tmp actual
  mkdir -p "$IPAMONA_CACHE_DIR"
  if [ -f "$IPAMONA_CACHE_FILE" ] && [ "$(sha256_file "$IPAMONA_CACHE_FILE")" = "$IPAMONA_SHA256" ]; then
    ok "IPAMona package: cached and verified"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "curl not found; cannot download IPAMona fonts"
  tmp="$(mktemp "$IPAMONA_CACHE_DIR/$IPAMONA_DIST.XXXXXX")"
  for url in "${IPAMONA_URLS[@]}"; do
    msg "Downloading IPAMona font package from FreeBSD:"
    msg "  $url"
    if curl -fL --progress-bar -o "$tmp" "$url"; then
      actual="$(sha256_file "$tmp")"
      if [ "$actual" = "$IPAMONA_SHA256" ]; then
        mv "$tmp" "$IPAMONA_CACHE_FILE"
        ok "IPAMona package: SHA-256 verified"
        return 0
      fi
      warn "IPAMona package hash mismatch from $url"
      warn "  actual:   $actual"
      warn "  expected: $IPAMONA_SHA256"
    fi
  done
  rm -f "$tmp"
  die "Could not download a verified IPAMona package from the FreeBSD mirrors"
}

install_ipamona_fonts() {
  local tmp root font source
  if have_ipamona_fonts; then
    ok "IPAMona fonts: present in ~/Library/Fonts"
    return 0
  fi

  download_ipamona_package
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dqx-ipamona.XXXXXX")"
  tar -xzf "$IPAMONA_CACHE_FILE" -C "$tmp"
  root="$tmp/opfc-ModuleHP-1.1.1_withIPAMonaFonts-1.0.8/fonts"
  mkdir -p "$HOME/Library/Fonts"
  for font in "${IPAMONA_FONT_FILES[@]}"; do
    source="$root/$font"
    [ -f "$source" ] || { rm -rf "$tmp"; die "Verified IPAMona package is missing fonts/$font"; }
    install -m 0644 "$source" "$HOME/Library/Fonts/$font"
  done
  rm -rf "$tmp"
  ok "IPAMona fonts: installed to ~/Library/Fonts"
}

cmd_patches() (
  local stage
  require_crossover
  check_crossover_build || exit 1
  msg "Checking CrossOver binary patches"
  stage="$(mktemp -d "${TMPDIR:-/tmp}/dqx-patches.XXXXXX")"
  trap 'rm -rf "$stage"' EXIT

  # Verify every input and output before replacing any installed module.
  prepare_patch "$WINEGSTREAMER_PE_TARGET" "$WINEGSTREAMER_PE_STOCK_HASH" "$WINEGSTREAMER_PE_HASH" "$stage/winegstreamer.dll"
  prepare_patch "$WINEGSTREAMER_UNIX_TARGET" "$WINEGSTREAMER_UNIX_STOCK_HASH" "$WINEGSTREAMER_UNIX_HASH" "$stage/winegstreamer.so"

  install_patch "$WINEGSTREAMER_PE_TARGET" "$WINEGSTREAMER_PE_STOCK_HASH" "$WINEGSTREAMER_PE_HASH" "$stage/winegstreamer.dll"
  install_patch "$WINEGSTREAMER_UNIX_TARGET" "$WINEGSTREAMER_UNIX_STOCK_HASH" "$WINEGSTREAMER_UNIX_HASH" "$stage/winegstreamer.so"
  if ! codesign --verify --strict "$CX_APP" 2>/dev/null; then
    msg "Signing the patched CrossOver bundle locally"
    codesign --force --sign - --preserve-metadata=identifier,entitlements,flags \
      --generate-entitlement-der "$CX_APP"
    codesign --verify --strict "$CX_APP"
  fi
)

cmd_binpack() (
  local pack="${1:-}" pack_abs actual tmp delta_dir=patches/crossover-26.3/binary-deltas
  [ -n "$pack" ] || die "Usage: ./dqx.sh binpack /path/to/binpack.zip"
  pack_abs="$(abs_existing_file "$pack")" || die "Binpack not found: $pack"

  if [ -n "${DQX_BINPACK_SHA256:-}" ]; then
    actual="$(sha256_file "$pack_abs")"
    [ "$actual" = "$DQX_BINPACK_SHA256" ] || die "Binpack hash mismatch: $actual"
    ok "Binpack zip: SHA-256 verified"
  else
    warn "DQX_BINPACK_SHA256 is not set; installing without zip-level hash verification"
  fi

  command -v unzip >/dev/null 2>&1 || die "unzip not found"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dqx-binpack.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  unzip -q "$pack_abs" -d "$tmp"
  [ -f "$tmp/manifest.json" ] || die "Binpack is missing manifest.json"
  if find "$tmp" -type f \( -name 'win32u.so' -o -name 'winegstreamer.dll' -o -name 'winegstreamer.so' \) | grep -q .; then
    die "Refusing binpack with full CrossOver modules; use .bsdiff deltas only"
  fi
  # shellcheck source=platform/binpack.sh
  source "$PLATFORM_DIR/binpack.sh"
  if [ -f "$tmp/bin/dqx-launcher-clip.exe" ]; then
    install_win32_binpack "$tmp" "$DQX_WIN32_BINPACK"
    ok "Win32 helper binpack installed to $DQX_WIN32_BINPACK"
  elif [ -d "$tmp/$delta_dir" ]; then
    [ -f "$tmp/$delta_dir/winegstreamer.dll.bsdiff" ] && [ -f "$tmp/$delta_dir/winegstreamer.so.bsdiff" ] \
      || die "CrossOver 26.3 patch binpack must contain both movie deltas"
    install_binpack_files "$tmp" "$DQX_CX_PATCH_BINPACK" \
      "$delta_dir/winegstreamer.dll.bsdiff" "$delta_dir/winegstreamer.so.bsdiff" manifest.json
    ok "CrossOver 26.3 patch binpack installed to $DQX_CX_PATCH_BINPACK"
  else
    die "Binpack is neither a win32 helper pack nor a CrossOver 26.3 patch pack"
  fi
)

fetch_one_binpack() (
  local label="$1" url="$2" expected="$3" cache_file="$4" download
  mkdir -p "$BINPACK_CACHE_DIR"
  if [ -f "$cache_file" ] && [ "$(sha256_file "$cache_file")" = "$expected" ]; then
    ok "$label binpack: cached and verified"
  else
    command -v curl >/dev/null 2>&1 || die "curl not found; cannot download binpacks"
    msg "Downloading $label binpack:"
    msg "  $url"
    download="$(mktemp "$cache_file.XXXXXX")"
    trap 'rm -f "$download"' EXIT
    curl -fL --progress-bar -o "$download" "$url"
    if [ "$(sha256_file "$download")" != "$expected" ]; then
      die "Downloaded $label binpack hash did not match the pinned release hash"
    fi
    mv "$download" "$cache_file"
    ok "$label binpack: SHA-256 verified"
  fi
  DQX_BINPACK_SHA256="$expected" cmd_binpack "$cache_file"
)

cmd_fetch_binpack() {
  local pack="$DQX_REPO_DIR/$CX_PATCH_BINPACK_DIST"
  if [ ! -f "$pack" ]; then
    pack="$DQX_REPO_DIR/build/binpack-release/$CX_PATCH_BINPACK_DIST"
  fi
  [ -f "$pack" ] || die "Missing $CX_PATCH_BINPACK_DIST. Use the user release archive or install the patch pack with './dqx.sh binpack /path/to/pack.zip'."
  DQX_BINPACK_SHA256="$CX_PATCH_BINPACK_SHA256" cmd_binpack "$pack"
  fetch_one_binpack "Win32 helper" "$WIN32_BINPACK_URL" "$WIN32_BINPACK_SHA256" \
    "$BINPACK_CACHE_DIR/$WIN32_BINPACK_DIST"
}

set_cxbottle_env() {
  local key="$1" value="$2" tmp awk_value
  [ -f "$CX_BOTTLE_CONF" ] || die "Bottle config not found: $CX_BOTTLE_CONF"
  awk_value="${value//\\/\\\\}"
  tmp="$(mktemp "${TMPDIR:-/tmp}/dqx-cxbottle.XXXXXX")"
  awk -v key="$key" -v value="$awk_value" '
    BEGIN {
      section = "[EnvironmentVariables]"
      newline = "\"" key "\" = \"" value "\""
      in_section = 0
      saw_section = 0
      wrote = 0
    }
    /^\[/ {
      if (in_section && !wrote) {
        print newline
        wrote = 1
      }
      in_section = ($0 == section)
      if (in_section) saw_section = 1
      print
      next
    }
    in_section {
      pattern = "^\"" key "\"[[:space:]]*="
      if ($0 ~ pattern) {
        if (!wrote) print newline
        wrote = 1
        next
      }
    }
    { print }
    END {
      if (!wrote) {
        if (!saw_section) {
          print ""
          print section
        }
        print newline
      }
    }
  ' "$CX_BOTTLE_CONF" >"$tmp"
  if cmp -s "$tmp" "$CX_BOTTLE_CONF"; then
    rm -f "$tmp"
    return 0
  fi
  cp -p "$CX_BOTTLE_CONF" "$(mktemp "$CX_BOTTLE_CONF.before-dqx-helper.XXXXXX")"
  mv "$tmp" "$CX_BOTTLE_CONF"
}

configure_bottle_env() {
  [ -f "$CX_BOTTLE_CONF" ] || die "Bottle does not exist yet: $CX_BOTTLE"
  msg "Writing durable CrossOver bottle environment"
  set_cxbottle_env "GST_PLUGIN_SYSTEM_PATH_1_0" "$GST_PLUGIN_DIR"
  set_cxbottle_env "GST_REGISTRY_1_0" "$GST_REGISTRY"
  set_cxbottle_env "WINEPATH" "$DQX_GAME_WIN"
  ok "Bottle environment configured in $CX_BOTTLE_CONF"
}

cmd_fonts() {
  require_crossover
  install_ipamona_fonts
  [ -x "$FONT_HELPER" ] || die "Font helper not found or not executable: $FONT_HELPER"
  CX_ROOT="$CX_ROOT" CX_BOTTLE="$CX_BOTTLE" "$FONT_HELPER"
}

cmd_setup() {
  cmd_patches
  if [ ! -d "$CX_BOTTLE_DIR/drive_c" ]; then
    msg "Creating CrossOver bottle '$CX_BOTTLE'"
    "$CX_ROOT/bin/cxbottle" --bottle "$CX_BOTTLE" --create --template win11_64
  else
    msg "Updating existing CrossOver bottle '$CX_BOTTLE'"
    cx --update-only
  fi
  configure_bottle_env
  cmd_fonts || warn "Font setup did not complete; run './dqx.sh doctor' for details."
  # CrossOver can keep a copy of the builtin 32-bit DLL in an existing bottle.
  install_patch "$BOTTLE_WINEGSTREAMER_PE" "$WINEGSTREAMER_PE_STOCK_HASH" \
    "$WINEGSTREAMER_PE_HASH" "$WINEGSTREAMER_PE_TARGET"
  ok "Setup pass complete. Next: ./dqx.sh install /path/to/Setup.exe"
}

cmd_install() {
  local setup="${1:-}" setup_abs setup_dir
  [ -n "$setup" ] || die "Usage: ./dqx.sh install /path/to/Setup.exe"
  setup_abs="$(abs_existing_file "$setup")" || die "Installer not found: $setup"
  require_crossover
  check_crossover_build || return 1
  [ -d "$CX_BOTTLE_DIR/drive_c" ] || die "No CrossOver bottle yet. Run './dqx.sh setup' first."
  setup_dir="$(dirname -- "$setup_abs")"
  msg "Running installer from its own directory:"
  msg "  workdir: $setup_dir"
  msg "  exe:     $setup_abs"
  cx_workdir "$setup_dir" "$setup_abs"
  if [ -f "$DQX_BOOT_DIR/DQXBoot.exe" ]; then
    ok "Base install detected at $DQX_UNIX_DIR"
  else
    warn "Did not find DQXBoot.exe after install."
    warn "Expected: $DQX_BOOT_DIR/DQXBoot.exe"
  fi
}

cmd_play() {
  local clip_helper=""
  require_crossover
  check_crossover_build || return 1
  [ -f "$DQX_BOOT_DIR/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."
  check_movie_patches || die "Run './dqx.sh setup' to refresh the movie patches before playing."
  configure_bottle_env
  if clip_helper="$(launcher_clip_helper)"; then
    msg "Starting updater progress redraw helper"
    cx --no-update "$clip_helper" &
  else
    warn "Updater progress helper missing. Run './dqx.sh fetch-binpack' to install it into: $DQX_WIN32_BINPACK"
  fi
  set -- "$CX_WINE" --bottle "$CX_BOTTLE" --no-update --workdir "$DQX_BOOT_DIR" DQXBoot.exe
  if [ "$DQX_INHIBIT" != 0 ] && command -v caffeinate >/dev/null 2>&1; then
    set -- caffeinate -dimsu "$@"
  fi
  msg "Launching DQXBoot.exe from $DQX_BOOT_DIR"
  (
    cd "$DQX_BOOT_DIR"
    "$@"
  )
}

check_file() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then ok "$label: $path"; else warn "$label: missing ($path)"; return 1; fi
}

check_rosetta() {
  if /usr/bin/pgrep oahd >/dev/null 2>&1 ||
     /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    ok "Rosetta 2: installed"
  else
    warn "Rosetta 2: not detected. Install with: softwareupdate --install-rosetta"
  fi
}

check_gstreamer() {
  local element status=0
  check_file "GStreamer framework" "$GST_INSPECT" || return 1
  for element in asfdemux avdec_wmv3 avdec_wmav2; do
    if GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_DIR" arch -x86_64 "$GST_INSPECT" "$element" >/dev/null 2>&1; then
      ok "GStreamer: $element available under x86_64"
    else
      warn "GStreamer: $element missing under x86_64"
      status=1
    fi
  done
  return "$status"
}

check_fonts() {
  local missing=0 font
  for font in "${IPAMONA_FONT_FILES[@]}"; do
    if [ ! -f "$HOME/Library/Fonts/$font" ]; then
      warn "IPAMona font missing: $HOME/Library/Fonts/$font"
      missing=1
    fi
  done
  if [ "$missing" = 0 ]; then
    ok "IPAMona fonts: present in ~/Library/Fonts"
  else
    warn "Run './dqx.sh setup' or './dqx.sh fonts' to download and install them from FreeBSD."
    return 1
  fi
}

check_cxbottle_env() {
  if [ ! -f "$CX_BOTTLE_CONF" ]; then
    warn "Bottle config: missing ($CX_BOTTLE_CONF)"
    return 1
  fi
  if grep -Fq "\"GST_PLUGIN_SYSTEM_PATH_1_0\" = \"$GST_PLUGIN_DIR\"" "$CX_BOTTLE_CONF"; then
    ok "Bottle env: GST_PLUGIN_SYSTEM_PATH_1_0 points at GStreamer.framework plugins"
  else
    warn "Bottle env: GST_PLUGIN_SYSTEM_PATH_1_0 is not configured"
  fi
  if grep -Fq "\"WINEPATH\" = \"$DQX_GAME_WIN\"" "$CX_BOTTLE_CONF"; then
    ok "Bottle env: WINEPATH points at DQX Game directory"
  else
    warn "Bottle env: WINEPATH is not configured"
  fi
}

cmd_doctor() {
  local status=0
  msg "macOS / CrossOver DQX doctor"
  if [ "$(uname -s)" = Darwin ]; then ok "OS: macOS"; else warn "OS: not macOS"; fi
  if [ "$(uname -m)" = arm64 ]; then ok "CPU: Apple Silicon"; else warn "CPU: not arm64"; fi
  check_rosetta
  require_crossover
  check_crossover_build || return 1
  ok "CrossOver build: $CX_SUPPORTED_BUILD"
  "$CX_WINE" --version 2>/dev/null | sed 's/^/   /' || true
  check_file "Bottle directory" "$CX_BOTTLE_DIR" || true
  check_cxbottle_env || true
  check_fonts || true
  check_gstreamer || status=1
  if ! check_movie_patches; then
    warn "Required CrossOver patches are incomplete. On a stock supported build, run './dqx.sh fetch-binpack' and './dqx.sh setup'."
    status=1
  fi
  if clip_helper="$(launcher_clip_helper)"; then
    ok "Updater progress helper: $clip_helper"
  else
    warn "Updater progress helper: missing. Run './dqx.sh fetch-binpack' to install it into $DQX_WIN32_BINPACK"
  fi
  if [ -f "$DQX_BOOT_DIR/DQXBoot.exe" ]; then
    ok "DQX install: found $DQX_BOOT_DIR/DQXBoot.exe"
  else
    warn "DQX install: not found yet"
  fi
  return "$status"
}

case "${1:-}" in
  doctor)  cmd_doctor ;;
  setup)   cmd_setup ;;
  fetch-binpack) cmd_fetch_binpack ;;
  patches) cmd_patches ;;
  binpack) shift; cmd_binpack "$@" ;;
  fonts)   cmd_fonts ;;
  install) shift; cmd_install "$@" ;;
  play)    cmd_play ;;
  ""|-h|--help|help) usage ;;
  *) die "Unknown command: $1 (try: doctor | setup | fetch-binpack | binpack | patches | fonts | install | play)" ;;
esac
