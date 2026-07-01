#!/usr/bin/env bash
#
# platform/linux.sh — Dragon Quest X Online (Japanese client) on Linux via plain Wine.
#
# A thin helper that creates a Wine prefix, runs YOUR OWN copy of the official DQX
# installer into it, and launches the game with the handful of non-obvious settings
# that make it work. It does NOT download or provide the game itself.
#
# Default path: plain Wine, no Steam or Lutris. GE-Proton11/umu remains an
# optional fallback. WineHQ 11 multilib builds must run DQX with WINEARCH=wow64;
# the helper detects that layout and selects the mode automatically.
# The game is a 32-bit DirectX 9 client; it runs through Wine's new-WoW64 mode
# and renders via wined3d (D3D9 -> OpenGL).
#
# Public domain (Unlicense). NO WARRANTY. See README.md and UNLICENSE.
#
# Usage:
#   ./dqx.sh doctor                  # check prerequisites
#   ./dqx.sh setup                   # create + provision a clean Wine prefix
#   ./dqx.sh fonts                   # install/refresh Japanese font aliases in a prefix
#   ./dqx.sh install /path/Setup.exe # run YOUR DQX installer into the prefix
#   ./dqx.sh play                    # launch the game with plain Wine
#   ./dqx.sh play-umu                # Ubuntu fallback: launch with GE-Proton11 via umu
#
# Config (override via environment):
#   DQX_PREFIX   Prefix location          (default: ~/Games/dqx-prefix)
#   WINE         Wine binary to use        (default: wine)
#   DQX_LOCALE   Japanese locale to use    (default: ja_JP.utf8)
#   DQX_WINEARCH Wine execution mode        (default: auto; win64 or wow64 override)
#   DQX_JP_FONT  Override: substitute the JP UI fonts with this host family instead of
#                installing IPAMona via winetricks (default: IPAMona if winetricks present)
#   DQX_INHIBIT  1=hold an idle/sleep lock while playing (default), 0=don't
#   DQX_BINPACK   Unpacked helper binpack    (default: ./vendor/binpack)
#   DQX_MOVIE_COMPAT_GAMEID  Opt-in Wine WMReader workaround (default: disabled;
#                            use 638160 for affected wine-cachyos 10.0 builds)
#   DQX_UMU      umu-run binary for play-umu (default: umu-run)
#   DQX_PROTONPATH  GE-Proton path for play-umu (default: auto-detect GE-Proton11-1)
#   DQX_UMU_GAMEID  UMU GAMEID for play-umu (default: dqx; deliberately no Steam app id)
set -euo pipefail

: "${DQX_PREFIX:=$HOME/Games/dqx-prefix}"
: "${WINE:=wine}"
: "${DQX_LOCALE:=ja_JP.utf8}"
: "${DQX_WINEARCH:=auto}"
: "${DQX_MOVIE_COMPAT_GAMEID:=}"
: "${DQX_UMU:=umu-run}"
: "${DQX_PROTONPATH:=}"
: "${DQX_UMU_GAMEID:=dqx}"

SCRIPT_FILE="$(readlink -f -- "${BASH_SOURCE[0]}")"
PLATFORM_DIR="${SCRIPT_FILE%/*}"
: "${DQX_REPO_DIR:=$(CDPATH= cd -- "$PLATFORM_DIR/.." && pwd -P)}"
SCRIPT_DIR="$DQX_REPO_DIR"
: "${DQX_BINPACK:=$DQX_REPO_DIR/vendor/binpack}"

GAME_REL="drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X"
GAME_WIN_GAMEDIR='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'
# Disable Mono/.NET (DQX doesn't need it) so its install prompt never appears.
# mshtml/Gecko is left ENABLED on purpose — the launcher's UI is HTML.
: "${DQX_DLLOVERRIDES:=mscoree=}"

# Japanese UI font names the DQX tools request; DQXConfig.exe in particular uses
# the localized/full-width MS Gothic names, so the fallback path must cover those
# exact faces instead of only the ASCII aliases.
JP_FONT_NAMES=(
  "MS Gothic" "MS PGothic" "MS Mincho" "MS PMincho"
  "ＭＳ ゴシック" "ＭＳ Ｐゴシック" "ＭＳ 明朝" "ＭＳ Ｐ明朝"
  "Meiryo" "Meiryo UI" "Yu Gothic" "Yu Gothic UI"
  "MS Sans Serif" "MS Shell Dlg" "MS Shell Dlg 2" "Tahoma"
)

msg()  { printf '\033[1;36m>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

launcher_clip_helper() {
  if [ -f "$DQX_BINPACK/bin/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$DQX_BINPACK/bin/dqx-launcher-clip.exe"
  elif [ -f "$SCRIPT_DIR/dqx-launcher-clip.exe" ]; then
    printf '%s\n' "$SCRIPT_DIR/dqx-launcher-clip.exe"
  else
    return 1
  fi
}

# --- Wine discovery / capability probing ---------------------------------------

have_wine() { command -v "$WINE" >/dev/null 2>&1; }

# "11.11" -> prints "11 11"; empty if unparseable.
wine_version_parts() {
  "$WINE" --version 2>/dev/null | sed -nE 's/^wine-([0-9]+)\.([0-9]+).*/\1 \2/p'
}

# Candidate DLL directories belonging to the selected Wine installation.
wine_dll_dirs() {
  local b root d
  b="$(command -v "$WINE" 2>/dev/null)" || return 0
  b="$(readlink -f "$b" 2>/dev/null || printf '%s' "$b")"
  root="${b%/bin/*}"
  for d in "$root"/lib/wine "$root"/lib64/wine "$root"/lib/*/wine; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done 2>/dev/null | sort -u
}

# Capability is separate from selection: a multilib Wine 11 installation can
# ship both old and new WoW64, and WINEARCH decides which one is active.
wine_has_new_wow64() {
  local d
  for d in $(wine_dll_dirs); do
    [ -f "$d/x86_64-windows/wow64.dll" ] && return 0
    [ -f "$d/wow64.dll" ] && return 0
  done
  return 1
}

wine_has_i386_unix() {
  local d
  for d in $(wine_dll_dirs); do
    [ -d "$d/i386-unix" ] && return 0
  done
  return 1
}

wine_major_version() {
  local parts
  parts="$(wine_version_parts)"
  [ -n "$parts" ] || return 1
  printf '%s\n' "${parts%% *}"
}

# Pure new-WoW64 builds have no i386 Unix loader, so a normal win64 prefix uses
# new WoW64 automatically. Dual/multilib Wine 11 builds default to old WoW64 and
# must be forced into the tested path with WINEARCH=wow64.
winearch_for_dqx() {
  local major
  case "$DQX_WINEARCH" in
    auto)
      if wine_has_i386_unix; then
        major="$(wine_major_version 2>/dev/null || true)"
        if wine_has_new_wow64 && [ "${major:-0}" -ge 11 ] 2>/dev/null; then
          printf '%s\n' wow64
        else
          printf '%s\n' win64
        fi
      else
        printf '%s\n' win64
      fi
      ;;
    win64|wow64) printf '%s\n' "$DQX_WINEARCH" ;;
    *) return 1 ;;
  esac
}

wine_mode_is_new_wow64() {
  local winearch
  winearch="$(winearch_for_dqx 2>/dev/null || true)"
  [ -n "$winearch" ] && wine_has_new_wow64 || return 1
  if wine_has_i386_unix; then
    [ "$winearch" = wow64 ]
  else
    return 0
  fi
}

# Best-effort: the Wine-Gecko version this build expects (mshtml.dll embeds it).
gecko_version() {
  local d f v
  for d in $(wine_dll_dirs); do
    for f in "$d"/x86_64-windows/mshtml.dll "$d"/i386-windows/mshtml.dll "$d"/*/mshtml.dll; do
      [ -f "$f" ] || continue
      v="$(strings -a "$f" 2>/dev/null | grep -aoE '^2\.[0-9]+\.[0-9]+$' | head -1)"
      [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
    done
  done
  return 1
}

# --- prefix-scoped Wine wrappers -----------------------------------------------

w() {
  local winearch
  winearch="$(winearch_for_dqx)" \
    || die "Invalid DQX_WINEARCH='$DQX_WINEARCH' (expected auto, win64, or wow64)."
  wine_mode_is_new_wow64 \
    || die "Selected Wine/WINEARCH=$winearch does not activate new WoW64. Run './dqx.sh doctor'."
  WINEPREFIX="$DQX_PREFIX" WINEARCH="$winearch" LC_ALL="$DQX_LOCALE" \
  WINEDLLOVERRIDES="$DQX_DLLOVERRIDES" "$WINE" "$@"
}
reg_add() { WINEDEBUG=-all w reg add "$@" >/dev/null 2>&1; }

apply_launcher_x11_settings() {
  # DQX paints its H&S warning before mapping the launcher HWND. Mutter clears
  # that early paint when it later manages/maps the window; an unmanaged X11
  # window preserves it. Keep this per-app rather than changing the whole prefix.
  reg_add 'HKCU\Software\Wine\AppDefaults\DQXLauncher.exe\X11 Driver' \
    /v Managed /t REG_SZ /d N /f
}

has_gecko_engine() { ls "$DQX_PREFIX"/drive_c/windows/*/gecko/*/wine_gecko/xul.dll >/dev/null 2>&1; }

# Resolve a JP font family that fontconfig actually has installed.
detect_jp_font() {
  if [ -n "${DQX_JP_FONT:-}" ]; then printf '%s\n' "$DQX_JP_FONT"; return 0; fi
  command -v fc-list >/dev/null 2>&1 || return 1
  local jal f
  jal="$(fc-list :lang=ja 2>/dev/null)"
  # Prefer Gothic faces whose metrics are closer to MS UI Gothic than Noto's.
  for f in "IPAPGothic" "IPAGothic" "VL PGothic" "VL Gothic" \
           "Source Han Sans JP" "Noto Sans CJK JP" "Sazanami Gothic"; do
    if grep -qiF "$f" <<<"$jal"; then printf '%s\n' "$f"; return 0; fi
  done
  # Fallback: whatever fontconfig resolves for Japanese.
  local fb; fb="$(fc-match -f '%{family[0]}' :lang=ja 2>/dev/null || true)"
  [ -n "$fb" ] && printf '%s\n' "$fb"
  return 0
}

# --- prerequisite checks -------------------------------------------------------

DOCTOR_OK=1
PLAIN_WINE_OK=1
GE_FALLBACK_OK=0
note_fail() { DOCTOR_OK=0; }

check_wine() {
  PLAIN_WINE_OK=1
  if ! have_wine; then
    warn "Wine: '$WINE' not found. Install Wine 11.11+ or set WINE=/path/to/wine."
    apt_hint "install WineHQ devel/staging; GE-Proton11 via './dqx.sh play-umu' remains an optional fallback"
    PLAIN_WINE_OK=0
    return
  fi

  local parts maj min ver winearch
  ver="$("$WINE" --version 2>/dev/null || true)"
  winearch="$(winearch_for_dqx 2>/dev/null || true)"
  if [ -z "$winearch" ]; then
    warn "Wine mode: invalid DQX_WINEARCH='$DQX_WINEARCH' (expected auto, win64, or wow64)."
    PLAIN_WINE_OK=0
    return
  fi

  parts="$(wine_version_parts)"
  if [ -z "$parts" ]; then
    warn "Wine: found '$WINE' but could not parse its version ($ver)."
  else
    read -r maj min <<<"$parts"
    if [ "$maj" -gt 11 ] 2>/dev/null || { [ "$maj" -eq 11 ] 2>/dev/null && [ "$min" -ge 11 ] 2>/dev/null; }; then
      ok "Wine: $ver (Wine 11.11 is verified on CachyOS and Ubuntu 24.04)"
    elif [ "$maj" -eq 11 ] 2>/dev/null; then
      warn "Wine: $ver is older than the verified Wine 11.11 baseline."
    elif [ "$maj" -ge 10 ] 2>/dev/null; then
      warn "Wine: $ver is older than the primary baseline; only selected downstream Wine 10 builds were tested."
    else
      warn "Wine: $ver is older than 10 and is unsupported by this helper."
      PLAIN_WINE_OK=0
    fi
  fi

  if ! wine_has_new_wow64; then
    warn "Wine layout: new-WoW64 capability not found in the selected Wine installation."
    PLAIN_WINE_OK=0
    return
  fi

  if wine_has_i386_unix; then
    if [ "$winearch" = wow64 ]; then
      ok "Wine layout: multilib/dual WoW64; active DQX mode is new WoW64 (WINEARCH=wow64)"
    else
      warn "Wine layout: multilib/dual WoW64, but WINEARCH=$winearch selects old WoW64."
      warn "  Use DQX_WINEARCH=auto (recommended) or DQX_WINEARCH=wow64."
      PLAIN_WINE_OK=0
    fi
  else
    ok "Wine layout: pure new-WoW64; active DQX prefix mode is WINEARCH=$winearch"
  fi
}

check_locale() {
  if locale -a 2>/dev/null | grep -qiE "^${DQX_LOCALE//./\\.}$|^ja_JP\.(utf8|UTF-8)$"; then
    ok "Locale '$DQX_LOCALE': present"
  else
    warn "Locale '$DQX_LOCALE': MISSING. The Japanese client needs a Japanese UTF-8 locale."
    apt_hint "sudo apt install locales && sudo locale-gen ja_JP.UTF-8"
    warn "  Generic fix: add 'ja_JP.UTF-8 UTF-8' to /etc/locale.gen and run locale-gen."
    note_fail
  fi
}

check_fonts() {
  if [ -n "${DQX_JP_FONT:-}" ]; then
    ok "Japanese fonts: will substitute with your DQX_JP_FONT='$DQX_JP_FONT' (host font)"
    return
  fi
  if ipamona_present; then ok "Japanese fonts: IPAMona already installed in prefix (metric-correct)"; return; fi
  if command -v winetricks >/dev/null 2>&1; then
    ok "Japanese fonts: winetricks present — setup installs IPAMona (metric-correct, self-contained)"
    return
  fi
  # No winetricks: fall back to substituting a host CJK font (text fine, dialog metrics may be off).
  warn "Japanese fonts: winetricks not found — setup will fall back to host-font substitution."
  warn "  Install winetricks for correct dialog layout (it installs IPAMona into the prefix)."
  if command -v fc-list >/dev/null 2>&1 && [ "$(fc-list :lang=ja 2>/dev/null | wc -l)" -gt 0 ]; then
    ok "  Host fallback OK: $(fc-list :lang=ja 2>/dev/null | wc -l) Japanese font(s) available ('$(detect_jp_font)')"
  else
    warn "  No host Japanese fonts either — install winetricks OR a CJK font, else text renders as tofu (□)."
    apt_hint "sudo apt install winetricks fonts-noto-cjk"
    note_fail
  fi
}

check_gstreamer() {
  if ! command -v gst-inspect-1.0 >/dev/null 2>&1; then
    warn "GStreamer (gst-inspect-1.0) not found — the launcher movie and in-game FMV cutscenes won't play."
    warn "  Install GStreamer + gst-libav (a.k.a. gstreamer1-libav / gst-plugins-libav)."
    apt_hint "sudo apt install gstreamer1.0-tools gstreamer1.0-libav gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly"
    note_fail; return
  fi

  local e missing=()
  for e in asfdemux avdec_wmv3 avdec_wmav2 videoconvert audioconvert audioresample; do
    gst-inspect-1.0 "$e" >/dev/null 2>&1 || missing+=("$e")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "FMV stack: GStreamer ASF demux + WMV3/WMA decode components present"
  else
    warn "FMV stack: missing GStreamer element(s): ${missing[*]}"
    warn "  Install gst-libav plus the base/good/bad/ugly plugin sets (package names vary by distro)."
    apt_hint "sudo apt install gstreamer1.0-tools gstreamer1.0-libav gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly"
    note_fail
  fi
}

check_graphics() {
  command -v nvidia-smi >/dev/null 2>&1 || return 0

  local driver
  driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
  [ -n "$driver" ] || return 0

  ok "NVIDIA driver: $driver (new WoW64 uses the 64-bit host OpenGL stack)"
}

check_gecko() {
  if has_gecko_engine; then ok "Gecko: installed in prefix (launcher HTML UI will render)"; return; fi
  local d
  for d in /usr/share/wine/gecko /usr/share/wine-gecko "$HOME/.cache/wine"; do
    ls "$d"/wine-gecko-*.msi >/dev/null 2>&1 && { ok "Gecko: installer MSI available ($d) — setup will install it"; return; }
  done
  local v; v="$(gecko_version || true)"
  if [ -n "$v" ]; then warn "Gecko: not installed yet (need $v). setup will download + install it (needs network)."
  else warn "Gecko: not installed; version undetected. Wine will prompt to install it on first launch."; fi
}

is_debian_like() {
  local id like
  id="$(os_release_value ID 2>/dev/null || true)"
  like="$(os_release_value ID_LIKE 2>/dev/null || true)"
  [ "$id" = debian ] || [ "$id" = ubuntu ] || grep -qw debian <<<"$like"
}

apt_hint() {
  is_debian_like || return 0
  warn "  Ubuntu/Debian package hint: $*"
}

check_tools() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v pgrep >/dev/null 2>&1 || missing+=(procps)
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "Helper tools: curl and pgrep present"
  else
    warn "Helper tools: missing ${missing[*]}"
    apt_hint "sudo apt install ${missing[*]}"
    note_fail
  fi
}

# --- Ubuntu GE-Proton / UMU fallback checks -----------------------------------

os_release_value() {
  local key="$1" line val
  [ -r /etc/os-release ] || return 1
  line="$(grep -E "^${key}=" /etc/os-release 2>/dev/null | head -1 || true)"
  [ -n "$line" ] || return 1
  val="${line#*=}"
  val="${val%\"}"
  val="${val#\"}"
  printf '%s\n' "$val"
}

is_ubuntu_host() {
  [ "$(os_release_value ID 2>/dev/null || true)" = ubuntu ]
}

wine_is_cachyos() {
  have_wine && "$WINE" --version 2>/dev/null | grep -qi 'cachyos'
}

find_ge_proton11() {
  local d
  for d in \
    "$HOME/.local/share/umu/compatibilitytools/GE-Proton11-1" \
    "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-1" \
    "$HOME/.steam/root/compatibilitytools.d/GE-Proton11-1" \
    "$HOME/.steam/steam/compatibilitytools.d/GE-Proton11-1" \
    /usr/local/share/umu/compatibilitytools/GE-Proton11-1 \
    /usr/share/umu/compatibilitytools/GE-Proton11-1 \
    /usr/local/share/steam/compatibilitytools.d/GE-Proton11-1 \
    /usr/share/steam/compatibilitytools.d/GE-Proton11-1; do
    [ -f "$d/proton" ] && [ -f "$d/toolmanifest.vdf" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

apparmor_enabled() {
  [ -r /sys/module/apparmor/parameters/enabled ] && grep -qi '^Y' /sys/module/apparmor/parameters/enabled
}

check_steamrt4_userns_profile() {
  apparmor_enabled || return 0
  [ -d "$HOME/.local/share/umu/steamrt4/pressure-vessel" ] || return 0

  local profile=/etc/apparmor.d/umu-pressure-vessel
  if [ ! -r "$profile" ]; then
    warn "Ubuntu GE-Proton path: local steamrt4 runtime present, but $profile is missing."
    warn "  If GE-Proton fails with 'bwrap: setting up uid map: Permission denied', add a userns AppArmor profile."
    return
  fi

  if grep -q 'steamrt4/pressure-vessel/bin/pressure-vessel-wrap' "$profile" \
     && grep -q 'steamrt4/pressure-vessel/libexec/steam-runtime-tools-0/srt-bwrap' "$profile"; then
    ok "Ubuntu GE-Proton path: local steamrt4 AppArmor userns profile configured"
  else
    warn "Ubuntu GE-Proton path: $profile does not cover local steamrt4 pressure-vessel/srt-bwrap."
    warn "  If GE-Proton fails with 'bwrap: setting up uid map: Permission denied', add steamrt4 entries."
  fi
}

check_ubuntu_geproton() {
  GE_FALLBACK_OK=0
  is_ubuntu_host || return 0

  local umu ge
  umu="$(command -v "$DQX_UMU" 2>/dev/null || true)"
  ge="$(recommended_ubuntu_protonpath || true)"

  if [ -n "$umu" ] && "$umu" --version >/dev/null 2>&1 \
     && [ -n "$ge" ] && [ -f "$ge/proton" ]; then
    GE_FALLBACK_OK=1
    ok "Optional fallback: GE-Proton11-1 via umu is available"
    check_steamrt4_userns_profile
    return
  fi

  msg "Optional fallback: GE-Proton11-1/umu is not fully available (plain Wine is preferred)."
  if [ -n "$umu" ] && ! "$umu" --version >/dev/null 2>&1; then
    warn "  '$DQX_UMU --version' failed."
  elif [ -z "$umu" ]; then
    msg "  umu-run not found."
  fi
  if [ -z "$ge" ] || [ ! -f "$ge/proton" ]; then
    msg "  GE-Proton11-1 not found."
  fi
}

recommended_ubuntu_protonpath() {
  [ -n "$DQX_PROTONPATH" ] && { printf '%s\n' "$DQX_PROTONPATH"; return 0; }
  find_ge_proton11
}

show_launch_advice() {
  local winearch
  section "Launch path"
  if [ "$PLAIN_WINE_OK" = 1 ]; then
    winearch="$(winearch_for_dqx)"
    ok "Recommended: ./dqx.sh play"
    msg "Uses plain $("$WINE" --version 2>/dev/null) with WINEARCH=$winearch."
    if [ "$GE_FALLBACK_OK" = 1 ]; then
      msg "Fallback available: ./dqx.sh play-umu (GE-Proton11-1 via umu)."
    fi
  elif [ "$GE_FALLBACK_OK" = 1 ]; then
    ok "Plain Wine is not ready; use fallback: ./dqx.sh play-umu"
    msg "Uses GE-Proton11-1 with PROTON_USE_WOW64=1."
  else
    warn "No verified launch path is ready. Fix the Wine mode above or install the GE-Proton11/umu fallback."
  fi
}

# --- commands ------------------------------------------------------------------

cmd_doctor() {
  DOCTOR_OK=1
  PLAIN_WINE_OK=1
  GE_FALLBACK_OK=0
  msg "Doctor checks the local machine only; it does not download or change anything."

  section "Runtime"
  check_wine
  check_ubuntu_geproton
  if [ "$PLAIN_WINE_OK" != 1 ] && [ "$GE_FALLBACK_OK" != 1 ]; then
    note_fail
  fi

  section "Language and launcher UI"
  check_locale
  check_fonts
  check_gecko

  section "Movies and graphics"
  if [ "$PLAIN_WINE_OK" = 1 ]; then
    check_gstreamer
    check_graphics
  elif [ "$GE_FALLBACK_OK" = 1 ]; then
    ok "Host GStreamer: not required by GE-Proton11-1 (it uses Wine DMO/FFmpeg)"
  else
    msg "Movie/graphics checks skipped until a runtime is ready."
  fi

  section "Helper tools"
  check_tools

  section "Game install"
  if [ -e "$DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe" ]; then ok "Game: installed at $DQX_PREFIX"
  else msg "Game: not installed yet. Next: ./dqx.sh setup && ./dqx.sh install /path/to/Setup.exe"; fi

  show_launch_advice

  echo
  if [ "$DOCTOR_OK" = 1 ]; then
    ok "Doctor passed. You are ready for the recommended launch path above."
  else
    warn "Doctor found missing pieces. Fix the items marked '!!', then run './dqx.sh doctor' again."
  fi
}

# Ensure the Gecko MSI is available so Wine can install it (system pkg, cache, or download).
ensure_gecko_msi() {
  local d
  for d in /usr/share/wine/gecko /usr/share/wine-gecko "$HOME/.cache/wine"; do
    ls "$d"/wine-gecko-*.msi >/dev/null 2>&1 && return 0
  done
  local v; v="$(gecko_version || true)"
  [ -n "$v" ] || { warn "Could not detect required Gecko version; Wine will prompt to install it on first launch."; return 1; }
  command -v curl >/dev/null 2>&1 || { warn "curl not found; cannot pre-download Gecko $v. Wine will prompt on first launch."; return 1; }
  local cache="$HOME/.cache/wine" base="https://dl.winehq.org/wine/wine-gecko/$v" m rc=0
  mkdir -p "$cache"
  for m in "wine-gecko-$v-x86.msi" "wine-gecko-$v-x86_64.msi"; do
    [ -f "$cache/$m" ] && continue
    msg "Downloading $m ..."
    curl -fL --progress-bar -o "$cache/$m" "$base/$m" || { warn "Download failed: $m"; rm -f "$cache/$m"; rc=1; }
  done
  return $rc
}

install_gecko() {
  has_gecko_engine && { msg "Gecko already present."; return 0; }
  ensure_gecko_msi || true
  local d m installed=0
  for d in "$HOME/.cache/wine" /usr/share/wine/gecko /usr/share/wine-gecko; do
    for m in "$d"/wine-gecko-*-x86.msi "$d"/wine-gecko-*-x86_64.msi; do
      [ -f "$m" ] || continue
      msg "Installing $(basename "$m") ..."
      WINEDEBUG=-all w msiexec /i "$m" /quiet || warn "msiexec returned nonzero for $(basename "$m")"
      installed=1
    done
    [ "$installed" = 1 ] && break
  done
  if has_gecko_engine; then ok "Gecko installed."
  else warn "Gecko engine not detected after setup — Wine may prompt to install it on first launch (that's fine)."; fi
}

ipamona_present() { [ -f "$DQX_PREFIX/drive_c/windows/Fonts/ipagui-mona.ttf" ]; }

# Make the metric-compatible aliases explicit even when winetricks installed the
# files. This protects us from verb changes and covers DQXConfig's localized
# dialog font name (`ＭＳ ゴシック`) directly.
apply_ipamona_aliases() {
  msg "Aliasing Japanese UI fonts -> IPAMona (metric-compatible)"
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS Gothic" /t REG_SZ /d "IPAMonaGothic" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS PGothic" /t REG_SZ /d "IPAMonaPGothic" /f
  # DQXLauncher's owner-drawn player list uses MS UI Gothic through GDI+.
  # Replacing that exact face can make the labels render blank on CrossOver.
  WINEDEBUG=-all w reg delete 'HKCU\Software\Wine\Fonts\Replacements' /v "MS UI Gothic" /f >/dev/null 2>&1 || true
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS Mincho" /t REG_SZ /d "IPAMonaMincho" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS PMincho" /t REG_SZ /d "IPAMonaPMincho" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS Shell Dlg" /t REG_SZ /d "IPAMonaUIGothic" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "MS Shell Dlg 2" /t REG_SZ /d "Tahoma" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "ＭＳ ゴシック" /t REG_SZ /d "IPAMonaGothic" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "ＭＳ Ｐゴシック" /t REG_SZ /d "IPAMonaPGothic" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "ＭＳ 明朝" /t REG_SZ /d "IPAMonaMincho" /f
  reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "ＭＳ Ｐ明朝" /t REG_SZ /d "IPAMonaPMincho" /f
}

# Substitute every JP UI font name with one host-installed family (fallback path).
apply_fonts_host() {
  local font="$1" name
  [ -n "$font" ] || { warn "No Japanese font found; skipping font substitution (text may be tofu)."; return; }
  msg "Substituting Japanese UI fonts -> '$font' (host font)"
  for name in "${JP_FONT_NAMES[@]}"; do
    reg_add 'HKCU\Software\Wine\Fonts\Replacements' /v "$name" /t REG_SZ /d "$font" /f
  done
}

apply_fonts() {
  # Explicit override: substitute with a user-chosen host font family.
  if [ -n "${DQX_JP_FONT:-}" ]; then apply_fonts_host "$DQX_JP_FONT"; return; fi
  if ipamona_present; then apply_ipamona_aliases; ok "Japanese fonts: IPAMona already installed and aliases refreshed."; return; fi
  # Preferred: IPAMona via winetricks. It's metric-compatible with MS PGothic / MS UI
  # Gothic (the fonts DQX's dialogs were laid out for), and installs INTO the prefix,
  # so dialogs render correctly and the setup is self-contained / portable. Other CJK
  # fonts render text fine but distort dialog layout (Noto: too big; VL Gothic: too small).
  if command -v winetricks >/dev/null 2>&1; then
    msg "Installing IPAMona Japanese fonts (winetricks fakejapanese_ipamona)..."
    # The verb should alias MS Gothic/PGothic/UI Gothic/Mincho/PMincho (+ JP-named
    # variants); apply our known-good aliases too so DQXConfig's full-width face name
    # cannot fall through to a bad host CJK font with different metrics.
    # Winetricks currently recognizes only win32/win64. The prefix itself remains
    # 64-bit; DQX is launched later with the independently selected new-WoW64 mode.
    if WINE="$WINE" WINEPREFIX="$DQX_PREFIX" WINEARCH=win64 WINEDEBUG=-all \
         winetricks -q fakejapanese_ipamona >/dev/null 2>&1 && ipamona_present; then
      apply_ipamona_aliases
      ok "Japanese fonts: IPAMona installed and aliased."
      return
    fi
    warn "winetricks fakejapanese_ipamona didn't complete; falling back to host-font substitution."
  else
    warn "winetricks not found — using host CJK font substitution (dialog metrics may be off)."
    warn "  For correct dialog layout, install winetricks (the script will then use IPAMona)."
  fi
  apply_fonts_host "$(detect_jp_font || true)"
}

cmd_fonts() {
  [ -d "$DQX_PREFIX/drive_c" ] || die "No prefix yet. Run ./dqx.sh setup first, or set DQX_PREFIX."
  have_wine || die "Wine ('$WINE') not found."
  apply_fonts
  warn "Restart every Wine process using this prefix before testing font/layout changes."
}

apply_tls() {
  msg "Enabling TLS 1.0/1.1/1.2 (the SE launcher refuses to connect otherwise)"
  reg_add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' \
    /v SecureProtocols /t REG_DWORD /d 0xA80 /f
  reg_add 'HKLM\Software\Microsoft\Windows\NT\CurrentVersion\WinHttp' \
    /v DefaultSecureProtocols /t REG_DWORD /d 0xA80 /f
  reg_add 'HKLM\Software\Wow6432Node\Microsoft\Windows\NT\CurrentVersion\WinHttp' \
    /v DefaultSecureProtocols /t REG_DWORD /d 0xA80 /f
}

cmd_setup() {
  have_wine || die "Wine ('$WINE') not found. Run './dqx.sh doctor'."
  local winearch
  winearch="$(winearch_for_dqx)" \
    || die "Invalid DQX_WINEARCH='$DQX_WINEARCH' (expected auto, win64, or wow64)."
  wine_mode_is_new_wow64 \
    || die "Selected Wine/WINEARCH=$winearch does not activate new WoW64. Run './dqx.sh doctor'."
  if [ -e "$DQX_PREFIX/drive_c" ]; then
    warn "Prefix already exists: $DQX_PREFIX"
    warn "Delete it (rm -rf \"$DQX_PREFIX\") or set DQX_PREFIX= to use another location."
    return 0
  fi
  mkdir -p "$DQX_PREFIX"
  msg "Creating a clean 64-bit Wine prefix at $DQX_PREFIX with WINEARCH=$winearch (this can take a minute)..."
  WINEDEBUG=-all w wineboot --init
  [ -d "$DQX_PREFIX/drive_c" ] || die "Prefix creation failed."
  install_gecko
  apply_fonts
  apply_tls
  ok "Prefix ready. Next: ./dqx.sh install /path/to/Setup.exe"
}

cmd_install() {
  local setup="${1:-}"
  [ -n "$setup" ] || die "Usage: ./dqx.sh install /path/to/Setup.exe"
  [ -f "$setup" ] || die "Installer not found: $setup"
  [ -d "$DQX_PREFIX/drive_c" ] || die "No prefix yet. Run ./dqx.sh setup first."
  have_wine || die "Wine ('$WINE') not found."
  setup="$(readlink -f "$setup")"
  msg "Running your DQX installer: $setup"
  msg "The installer is Japanese-only; just click through and install to the DEFAULT location."
  ( cd "$(dirname "$setup")" && w "$setup" )
  if [ -e "$DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe" ]; then
    ok "Base install detected. Next: ./dqx.sh doctor, then use the recommended play command."
  else
    warn "Did not find DQXBoot.exe afterward — did the installer use the default path?"
    warn "Expected: $DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe"
  fi
}

cmd_play_umu() {
  local boot="$DQX_PREFIX/$GAME_REL/Boot"
  [ -f "$boot/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."

  local umu ge
  umu="$(command -v "$DQX_UMU" 2>/dev/null || true)"
  [ -n "$umu" ] || die "umu-run not found. Install umu or set DQX_UMU=/path/to/umu-run."
  ge="$(recommended_ubuntu_protonpath || true)"
  [ -n "$ge" ] || die "GE-Proton11-1 not found. Install it or set DQX_PROTONPATH=/path/to/GE-Proton11-1."
  [ -f "$ge/proton" ] || die "Invalid DQX_PROTONPATH (missing proton): $ge"

  local -a inhibit=()
  if [ "${DQX_INHIBIT:-1}" != 0 ]; then
    command -v systemd-inhibit >/dev/null 2>&1 && inhibit+=(
      systemd-inhibit --what=idle:sleep --who="Dragon Quest X"
      --why="Gameplay (controller input does not reset the idle timer)")
    command -v kde-inhibit >/dev/null 2>&1 && inhibit+=(kde-inhibit --power --screenSaver)
  fi

  msg "Launching DQX with GE-Proton11 via umu."
  msg "Using PROTONPATH=$ge"
  msg "Using PROTON_USE_WOW64=1 (required for the launcher -> DQXTitle movie handoff)."
  ( cd "$boot" && \
    "${inhibit[@]}" env \
      PROTONPATH="$ge" PROTON_USE_WOW64=1 GAMEID="$DQX_UMU_GAMEID" \
      WINEPREFIX="$DQX_PREFIX" LC_ALL="$DQX_LOCALE" \
      "$umu" "$boot/DQXBoot.exe" )
}

cmd_play() {
  have_wine || die "Wine ('$WINE') not found."
  local boot="$DQX_PREFIX/$GAME_REL/Boot" winearch launcher_helper=""
  winearch="$(winearch_for_dqx)" \
    || die "Invalid DQX_WINEARCH='$DQX_WINEARCH' (expected auto, win64, or wow64)."
  wine_mode_is_new_wow64 \
    || die "Selected Wine/WINEARCH=$winearch does not activate new WoW64. Run './dqx.sh doctor'."
  [ -f "$boot/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."
  if ! apply_launcher_x11_settings; then
    warn "Could not set the per-app unmanaged X11 workaround; the H&S warning may be black."
  fi
  if launcher_helper="$(launcher_clip_helper)"; then
    :
  else
    warn "Updater redraw helper is missing. Install the optional binpack into: $DQX_BINPACK"
    warn "The updater still works, but moving its window may black out part of the progress bar."
  fi

  # Keep the machine awake for the game's lifetime. Gamepad input does NOT reset the
  # idle timer, so without this the screen can blank/lock or the box can suspend mid-game.
  #   systemd-inhibit (logind): blocks auto-suspend + idle actions (portable).
  #   kde-inhibit (Plasma):     also blocks KDE's screen locker + blanking, which the
  #                             logind idle lock alone doesn't reliably stop on KDE.
  # Both are nested, so each applies where present. Set DQX_INHIBIT=0 to disable.
  local -a inhibit=()
  local -a movie_env=()
  # This borrows a Proton/wine-cachyos app-compat ID that forces decoded BGRx
  # samples. WineHQ 11.11 does not need it; keep it opt-in for affected builds.
  if [ -n "$DQX_MOVIE_COMPAT_GAMEID" ]; then
    warn "Enabling opt-in WMReader workaround: SteamGameId=$DQX_MOVIE_COMPAT_GAMEID"
    movie_env+=(SteamGameId="$DQX_MOVIE_COMPAT_GAMEID")
  elif wine_is_cachyos; then
    msg "Movie workaround is disabled; if wine-cachyos 10.0 shows a blank WMV window, retry with DQX_MOVIE_COMPAT_GAMEID=638160."
  fi
  if [ "${DQX_INHIBIT:-1}" != 0 ]; then
    command -v systemd-inhibit >/dev/null 2>&1 && inhibit+=(
      systemd-inhibit --what=idle:sleep --who="Dragon Quest X"
      --why="Gameplay (controller input does not reset the idle timer)")
    command -v kde-inhibit >/dev/null 2>&1 && inhibit+=(kde-inhibit --power --screenSaver)
  fi
  msg "Launching DQX with $("$WINE" --version 2>/dev/null), WINEARCH=$winearch."
  msg "Launcher rendering workarounds: unmanaged H&S window; updater-only child clipping."
  msg "First run drops into the updater (downloads/patches the client) — let it finish."
  msg "Tip: a transient 'DQ-10009 / can't connect' right after the first boot update is harmless; rerun 'play'."
  # cd into Boot (DQXBoot.exe lives there); WINEPATH puts the Game dir on the exe
  # search path so the launcher can spawn DQXGame.exe by bare name after login.
  # DQXBoot.exe is a bootstrapper: it spawns DQXLauncher.exe / DQXGame.exe as separate
  # processes and exits within seconds. So we can't just wrap `wine DQXBoot.exe` — the
  # wake lock would release while you're still playing. Launch it, then poll until the
  # game's child processes are gone, keeping the inhibit held for the whole session.
  # We match the child EXEs (Launcher/Game/...), deliberately NOT DQXBoot — its name and
  # the game path are on our own wrapper's command line, and matching those would make
  # pgrep find this very process and loop forever. The parenthesized regex also can't
  # match its own literal text.
  # shellcheck disable=SC2016 # Expand $WINE inside the child shell after env sets it.
  ( cd "$boot" && \
    "${inhibit[@]}" env \
      "${movie_env[@]}" \
      WINEPREFIX="$DQX_PREFIX" WINEARCH="$winearch" LC_ALL="$DQX_LOCALE" \
      WINEDLLOVERRIDES="$DQX_DLLOVERRIDES" WINEPATH="$GAME_WIN_GAMEDIR" WINE="$WINE" \
      DQX_LAUNCHER_CLIP_HELPER="$launcher_helper" \
      sh -c '
        if [ -n "$DQX_LAUNCHER_CLIP_HELPER" ]; then
          "$WINE" "$DQX_LAUNCHER_CLIP_HELPER" &
          launcher_clip_pid=$!
        fi
        "$WINE" DQXBoot.exe
        sleep 5
        while pgrep -fi "dqx(launcher|game|title|config|updater)\.exe" >/dev/null 2>&1; do sleep 10; done
        if [ -n "${launcher_clip_pid:-}" ]; then
          wait "$launcher_clip_pid" 2>/dev/null || true
        fi
      ' )
}

case "${1:-}" in
  doctor)  cmd_doctor ;;
  setup)   cmd_setup ;;
  fonts)   cmd_fonts ;;
  install) shift; cmd_install "$@" ;;
  play)    cmd_play ;;
  play-umu|play-ge) cmd_play_umu ;;
  ""|-h|--help|help)
    sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "Unknown command: $1  (try: doctor | setup | fonts | install | play | play-umu)" ;;
esac
