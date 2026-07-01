#!/usr/bin/env bash
#
# macos-crossover.sh - Dragon Quest X Online on Apple Silicon CrossOver.
#
# This helper targets the currently verified minimal CrossOver path:
#   - CrossOver 26.2 in /Applications/CrossOver.app
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
#   ./macos-crossover.sh doctor
#   ./macos-crossover.sh setup
#   ./macos-crossover.sh fetch-binpack
#   ./macos-crossover.sh binpack /path/to/binpack.zip
#   ./macos-crossover.sh patches
#   ./macos-crossover.sh fonts
#   ./macos-crossover.sh install /path/to/Setup.exe
#   ./macos-crossover.sh play
#
# Config:
#   CX_APP        CrossOver app bundle       (default: /Applications/CrossOver.app)
#   CX_BOTTLE     CrossOver bottle name      (default: DQX)
#   DQX_PATCH_DIR Local patch artifact dir   (default: ./patches/crossover-26.2/artifacts)
#   DQX_BINPACK   Unpacked helper binpack    (default: ./vendor/binpack)
#   DQX_BINPACK_SHA256  Optional expected SHA-256 for ./macos-crossover.sh binpack
#   DQX_INHIBIT   1=hold a caffeinate lock   (default: 1)

set -euo pipefail

: "${CX_APP:=/Applications/CrossOver.app}"
: "${CX_BOTTLE:=DQX}"
: "${DQX_INHIBIT:=1}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
: "${DQX_PATCH_DIR:=$SCRIPT_DIR/patches/crossover-26.2/artifacts}"
: "${DQX_BINPACK:=$SCRIPT_DIR/vendor/binpack}"

CX_ROOT="$CX_APP/Contents/SharedSupport/CrossOver"
CX_WINE="$CX_ROOT/bin/wine"
CX_BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$CX_BOTTLE"
CX_BOTTLE_CONF="$CX_BOTTLE_DIR/cxbottle.conf"

DQX_REL='drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X'
DQX_UNIX_DIR="$CX_BOTTLE_DIR/$DQX_REL"
DQX_BOOT_DIR="$DQX_UNIX_DIR/Boot"
DQX_GAME_WIN='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'

BINPACK_RELEASE_TAG="macos-crossover-26.2-binpack-v20260701"
BINPACK_DIST="dqx-wine-helper-macos-crossover-26.2-binpack-v20260701.zip"
BINPACK_URL="https://github.com/AberrantWolf/dqx-proton-helper/releases/download/$BINPACK_RELEASE_TAG/$BINPACK_DIST"
BINPACK_SHA256="794dbaca3e50cc6b52ecfbc13d129641b86f29026d7c1326d1494c40095fbc01"
BINPACK_CACHE_DIR="$HOME/Library/Caches/dqx-wine-helper/binpack"
BINPACK_CACHE_FILE="$BINPACK_CACHE_DIR/$BINPACK_DIST"

GST_ROOT="/Library/Frameworks/GStreamer.framework/Versions/1.0"
GST_INSPECT="$GST_ROOT/bin/gst-inspect-1.0"
GST_PLUGIN_DIR="$GST_ROOT/lib/gstreamer-1.0"
GST_REGISTRY="$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin"

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

WIN32U_HASH='761e3f607c7814de5aa88b9c07b0b7368ead3acd27d62ff0e5031bddc84ad45d'
WINEGSTREAMER_PE_HASH='605caa4af8a159ef0a5aa258e06d7680b22f57b610095c4988e6a87914b1491a'
WINEGSTREAMER_UNIX_HASH='8680c71a1991d51eebabe3132e127557877e7e35c6d0420ca767276c0b5250ad'

WIN32U_TARGET="$CX_ROOT/lib/wine/x86_64-unix/win32u.so"
WINEGSTREAMER_PE_TARGET="$CX_ROOT/lib/wine/i386-windows/winegstreamer.dll"
WINEGSTREAMER_UNIX_TARGET="$CX_ROOT/lib/wine/x86_64-unix/winegstreamer.so"

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
  if [ -f "$DQX_BINPACK/bin/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$DQX_BINPACK/bin/dqx-launcher-clip.exe"
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

patch_artifact() {
  local name="$1" target="$2" expected="$3" source="$4" actual backup
  if [ -f "$target" ] && [ "$(sha256_file "$target")" = "$expected" ]; then
    ok "$name: already patched"
    return 0
  fi
  [ -f "$source" ] || {
    warn "$name: no local patch artifact at $source"
    return 1
  }
  actual="$(sha256_file "$source")"
  [ "$actual" = "$expected" ] || die "$name artifact hash mismatch: $source"
  [ -f "$target" ] || die "$name target missing: $target"

  backup="$target.stock-before-dqx-$(date +%Y%m%d-%H%M%S)"
  msg "Backing up $(basename "$target") -> $(basename "$backup")"
  cp -p "$target" "$backup"
  cp -p "$source" "$target"
  codesign --force --sign - "$target" >/dev/null 2>&1 || warn "$name: ad-hoc codesign failed"
  check_hash "$name" "$target" "$expected"
}

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

cmd_patches() {
  require_crossover
  msg "Checking CrossOver binary patches"
  patch_artifact "win32u.so H&S patch" \
    "$WIN32U_TARGET" "$WIN32U_HASH" "$DQX_PATCH_DIR/win32u.so" || true
  patch_artifact "winegstreamer.dll WMA-DMO patch" \
    "$WINEGSTREAMER_PE_TARGET" "$WINEGSTREAMER_PE_HASH" "$DQX_PATCH_DIR/winegstreamer.dll" || true
  patch_artifact "winegstreamer.so source-built GStreamer framework bridge" \
    "$WINEGSTREAMER_UNIX_TARGET" "$WINEGSTREAMER_UNIX_HASH" "$DQX_PATCH_DIR/winegstreamer.so" || true
}

cmd_binpack() {
  local pack="${1:-}" pack_abs actual tmp
  [ -n "$pack" ] || die "Usage: ./macos-crossover.sh binpack /path/to/binpack.zip"
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
  unzip -q "$pack_abs" -d "$tmp"
  [ -f "$tmp/manifest.json" ] || { rm -rf "$tmp"; die "Binpack is missing manifest.json"; }
  if find "$tmp" -type f \( -name 'win32u.so' -o -name 'winegstreamer.dll' -o -name 'winegstreamer.so' \) | grep -q .; then
    rm -rf "$tmp"
    die "Refusing binpack with full CrossOver modules; use .bsdiff deltas only"
  fi

  rm -rf "$DQX_BINPACK"
  mkdir -p "$DQX_BINPACK"
  cp -R "$tmp/." "$DQX_BINPACK/"
  rm -rf "$tmp"
  ok "Binpack installed to $DQX_BINPACK"
}

cmd_fetch_binpack() {
  mkdir -p "$BINPACK_CACHE_DIR"
  if [ -f "$BINPACK_CACHE_FILE" ] && [ "$(sha256_file "$BINPACK_CACHE_FILE")" = "$BINPACK_SHA256" ]; then
    ok "Binpack: cached and verified"
  else
    command -v curl >/dev/null 2>&1 || die "curl not found; cannot download the binpack"
    msg "Downloading optional helper binpack:"
    msg "  $BINPACK_URL"
    curl -fL --progress-bar -o "$BINPACK_CACHE_FILE.tmp" "$BINPACK_URL"
    if [ "$(sha256_file "$BINPACK_CACHE_FILE.tmp")" != "$BINPACK_SHA256" ]; then
      rm -f "$BINPACK_CACHE_FILE.tmp"
      die "Downloaded binpack hash did not match the pinned release hash"
    fi
    mv "$BINPACK_CACHE_FILE.tmp" "$BINPACK_CACHE_FILE"
    ok "Binpack: SHA-256 verified"
  fi
  DQX_BINPACK_SHA256="$BINPACK_SHA256" cmd_binpack "$BINPACK_CACHE_FILE"
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
  cp -p "$CX_BOTTLE_CONF" "$CX_BOTTLE_CONF.before-dqx-helper-$(date +%Y%m%d-%H%M%S)"
  mv "$tmp" "$CX_BOTTLE_CONF"
}

configure_bottle_env() {
  [ -f "$CX_BOTTLE_CONF" ] || die "Bottle does not exist yet: $CX_BOTTLE"
  msg "Writing durable CrossOver bottle environment"
  set_cxbottle_env "GST_PLUGIN_PATH" "$GST_PLUGIN_DIR"
  set_cxbottle_env "WINEPATH" "$DQX_GAME_WIN"
  if [ -f "$GST_REGISTRY" ]; then
    mv "$GST_REGISTRY" "$GST_REGISTRY.before-dqx-helper-$(date +%Y%m%d-%H%M%S)"
    msg "Moved GStreamer registry aside so CrossOver rescans plugins"
  fi
  ok "Bottle environment configured in $CX_BOTTLE_CONF"
}

cmd_fonts() {
  require_crossover
  install_ipamona_fonts
  [ -x "$FONT_HELPER" ] || die "Font helper not found or not executable: $FONT_HELPER"
  CX_ROOT="$CX_ROOT" CX_BOTTLE="$CX_BOTTLE" "$FONT_HELPER"
}

cmd_setup() {
  require_crossover
  if [ ! -d "$CX_BOTTLE_DIR/drive_c" ]; then
    msg "Creating CrossOver bottle '$CX_BOTTLE'"
    cx wineboot --init
  else
    msg "Using existing CrossOver bottle '$CX_BOTTLE'"
  fi
  configure_bottle_env
  cmd_fonts || warn "Font setup did not complete; run './macos-crossover.sh doctor' for details."
  cmd_patches
  ok "Setup pass complete. Next: ./macos-crossover.sh install /path/to/Setup.exe"
}

cmd_install() {
  local setup="${1:-}" setup_abs setup_dir
  [ -n "$setup" ] || die "Usage: ./macos-crossover.sh install /path/to/Setup.exe"
  setup_abs="$(abs_existing_file "$setup")" || die "Installer not found: $setup"
  [ -d "$CX_BOTTLE_DIR/drive_c" ] || die "No CrossOver bottle yet. Run './macos-crossover.sh setup' first."
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
  local -a wake=()
  local clip_helper=""
  require_crossover
  [ -f "$DQX_BOOT_DIR/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."
  configure_bottle_env
  if clip_helper="$(launcher_clip_helper)"; then
    msg "Starting updater progress redraw helper"
    cx "$clip_helper" &
  else
    warn "Updater progress helper missing. Install the optional binpack into: $DQX_BINPACK"
  fi
  if [ "$DQX_INHIBIT" != 0 ] && command -v caffeinate >/dev/null 2>&1; then
    wake=(caffeinate -dimsu)
  fi
  msg "Launching DQXBoot.exe from $DQX_BOOT_DIR"
  (
    cd "$DQX_BOOT_DIR"
    "${wake[@]}" "$CX_WINE" --bottle "$CX_BOTTLE" --workdir "$DQX_BOOT_DIR" DQXBoot.exe
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
  check_file "GStreamer framework" "$GST_INSPECT" || return 1
  if arch -x86_64 "$GST_INSPECT" avdec_wmv3 >/dev/null 2>&1; then
    ok "GStreamer: avdec_wmv3 available under x86_64"
  else
    warn "GStreamer: avdec_wmv3 missing under x86_64"
  fi
  if arch -x86_64 "$GST_INSPECT" avdec_wmav2 >/dev/null 2>&1; then
    ok "GStreamer: avdec_wmav2 available under x86_64"
  else
    warn "GStreamer: avdec_wmav2 missing under x86_64"
  fi
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
    warn "Run './macos-crossover.sh setup' or './macos-crossover.sh fonts' to download and install them from FreeBSD."
    return 1
  fi
}

check_cxbottle_env() {
  if [ ! -f "$CX_BOTTLE_CONF" ]; then
    warn "Bottle config: missing ($CX_BOTTLE_CONF)"
    return 1
  fi
  if grep -Fq "\"GST_PLUGIN_PATH\" = \"$GST_PLUGIN_DIR\"" "$CX_BOTTLE_CONF"; then
    ok "Bottle env: GST_PLUGIN_PATH points at GStreamer.framework plugins"
  else
    warn "Bottle env: GST_PLUGIN_PATH is not configured"
  fi
  if grep -Fq "\"WINEPATH\" = \"$DQX_GAME_WIN\"" "$CX_BOTTLE_CONF"; then
    ok "Bottle env: WINEPATH points at DQX Game directory"
  else
    warn "Bottle env: WINEPATH is not configured"
  fi
}

cmd_doctor() {
  msg "macOS / CrossOver DQX doctor"
  if [ "$(uname -s)" = Darwin ]; then ok "OS: macOS"; else warn "OS: not macOS"; fi
  if [ "$(uname -m)" = arm64 ]; then ok "CPU: Apple Silicon"; else warn "CPU: not arm64"; fi
  check_rosetta
  check_file "CrossOver app" "$CX_APP" || true
  check_file "CrossOver wine wrapper" "$CX_WINE" || true
  if [ -x "$CX_WINE" ]; then
    "$CX_WINE" --version 2>/dev/null | sed 's/^/   /' || true
  fi
  check_file "Bottle directory" "$CX_BOTTLE_DIR" || true
  check_cxbottle_env || true
  check_fonts || true
  check_gstreamer || true
  check_hash "win32u.so H&S patch" "$WIN32U_TARGET" "$WIN32U_HASH" || true
  check_hash "winegstreamer.dll WMA-DMO patch" "$WINEGSTREAMER_PE_TARGET" "$WINEGSTREAMER_PE_HASH" || true
  check_hash "winegstreamer.so source-built GStreamer framework bridge" "$WINEGSTREAMER_UNIX_TARGET" "$WINEGSTREAMER_UNIX_HASH" || true
  if clip_helper="$(launcher_clip_helper)"; then
    ok "Updater progress helper: $clip_helper"
  else
    warn "Updater progress helper: missing. Install the optional binpack into $DQX_BINPACK"
  fi
  if [ -f "$DQX_BOOT_DIR/DQXBoot.exe" ]; then
    ok "DQX install: found $DQX_BOOT_DIR/DQXBoot.exe"
  else
    warn "DQX install: not found yet"
  fi
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
