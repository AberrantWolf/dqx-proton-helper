#!/usr/bin/env bash
#
# dqx.sh — Dragon Quest X (Japanese client) on Linux via Proton, outside Steam.
#
# This is a thin helper around `umu-run` that creates a Proton prefix, runs YOUR
# own copy of the official DQX installer into it, and launches the game with the
# handful of settings that make it work. It does NOT download or provide the game.
#
# Public domain (Unlicense). NO WARRANTY. See README.md and UNLICENSE.
#
# Usage:
#   ./dqx.sh doctor                 # check prerequisites
#   ./dqx.sh setup                  # create a clean Proton prefix
#   ./dqx.sh install <Setup.exe>    # run YOUR DQX All-In-One installer into the prefix
#   ./dqx.sh play                   # launch the game (first run downloads/patches ~31 GB)
#
# Config (override via environment):
#   DQX_PREFIX   Prefix location           (default: ~/Games/dqx-prefix)
#   PROTONPATH   Proton build directory    (default: auto-detected; see "doctor")
#
set -euo pipefail

: "${DQX_PREFIX:=$HOME/Games/dqx-prefix}"
GAME_REL="drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X"
GAME_WIN_GAMEDIR='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'

msg()  { printf '\033[1;36m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

# Find a Proton build. The game client crashes without Proton's "new WoW64" mode,
# so a Proton build (GE-Proton >= 10-34, or proton-cachyos) is required — plain
# Wine will not work. Override with PROTONPATH=/path/to/proton-build.
detect_proton() {
  if [ -n "${PROTONPATH:-}" ]; then printf '%s\n' "$PROTONPATH"; return; fi
  local base d
  for base in \
      /usr/share/steam/compatibilitytools.d \
      "$HOME/.steam/steam/compatibilitytools.d" \
      "$HOME/.local/share/Steam/compatibilitytools.d" \
      "$HOME/.steam/root/compatibilitytools.d"; do
    [ -d "$base" ] || continue
    # Prefer proton-cachyos, then the highest-sorting GE-Proton, then anything.
    for d in "$base"/*cachyos* "$base"/GE-Proton* "$base"/*; do
      if [ -x "$d/proton" ]; then printf '%s\n' "$d"; return; fi
    done
  done
  printf '%s\n' ""
}

require_proton() {
  PROTONPATH="$(detect_proton)"
  [ -n "$PROTONPATH" ] && [ -x "$PROTONPATH/proton" ] || die \
"No Proton build found. Install GE-Proton (>= 10-34) or proton-cachyos into a
 Steam compatibilitytools.d directory, or set PROTONPATH=/path/to/proton-build.
 IMPORTANT: it must be a Proton build with new-WoW64 support. Plain Wine will
 not work — the game client crashes (null deref) without it."
  msg "Proton: $PROTONPATH"
}

# Run a command through umu-run with the DQX environment.
# Any WINEPATH exported by the caller is inherited (used by 'play').
# If DQX_INHIBIT!=0 (set by 'play'), wrap in systemd-inhibit so the desktop
# doesn't sleep/blank during gameplay — gamepad input does NOT reset the
# Wayland idle timer, so we hold an idle+sleep lock for the game's lifetime.
umu_run() {
  command -v umu-run >/dev/null 2>&1 || die "umu-run not found — install umu-launcher."
  local -a inhibit=()
  if [ "${DQX_INHIBIT:-0}" != 0 ] && command -v systemd-inhibit >/dev/null 2>&1; then
    inhibit=(systemd-inhibit --what=idle:sleep --who="Dragon Quest X"
             --why="Gameplay (controller input does not reset the idle timer)")
  fi
  "${inhibit[@]}" env \
    GAMEID=0 \
    PROTONPATH="$PROTONPATH" \
    WINEPREFIX="$DQX_PREFIX" \
    STEAM_COMPAT_DATA_PATH="$DQX_PREFIX" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/steam}" \
    PROTON_VERB="${PROTON_VERB:-waitforexitandrun}" \
    PROTON_USE_WOW64=1 \
    LC_ALL=ja_JP.utf8 \
    umu-run "$@"
}

cmd_doctor() {
  local ok=1
  if command -v umu-run >/dev/null 2>&1; then msg "umu-run: $(command -v umu-run)"
  else warn "umu-run: MISSING (install umu-launcher)"; ok=0; fi
  local p; p="$(detect_proton)"
  if [ -n "$p" ]; then msg "Proton: $p"
  else warn "Proton: none found (install GE-Proton >=10-34 / proton-cachyos, or set PROTONPATH)"; ok=0; fi
  if locale -a 2>/dev/null | grep -qiE '^ja_JP\.(utf8|UTF-8)$'; then msg "Locale ja_JP.utf8: present"
  else warn "Locale ja_JP.utf8: MISSING (generate it; the JP client needs it)"; ok=0; fi
  if [ -e "$DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe" ]; then msg "Game: installed at $DQX_PREFIX"
  else msg "Game: not installed yet (run 'setup' then 'install <Setup.exe>')"; fi
  [ "$ok" = 1 ] && msg "Prerequisites OK." || warn "Some prerequisites are missing (see above)."
}

cmd_setup() {
  require_proton
  if [ -e "$DQX_PREFIX/drive_c" ]; then
    warn "Prefix already exists: $DQX_PREFIX"
    warn "Delete it (rm -rf \"$DQX_PREFIX\") or set DQX_PREFIX= to use another location."
    return 0
  fi
  mkdir -p "$DQX_PREFIX"
  msg "Creating clean Proton prefix at $DQX_PREFIX (this can take a minute)..."
  PROTON_VERB=run umu_run wineboot --init
  [ -d "$DQX_PREFIX/drive_c" ] || die "Prefix creation failed."
  msg "Prefix ready. Next: ./dqx.sh install /path/to/Setup.exe"
}

cmd_install() {
  local setup="${1:-}"
  [ -n "$setup" ] || die "Usage: ./dqx.sh install /path/to/Setup.exe"
  [ -f "$setup" ] || die "Installer not found: $setup"
  [ -d "$DQX_PREFIX/drive_c" ] || die "No prefix yet. Run ./dqx.sh setup first."
  require_proton
  msg "Running your DQX installer: $setup"
  msg "Click through the installer GUI; install to the DEFAULT location."
  umu_run "$setup"
  if [ -e "$DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe" ]; then
    msg "Base install detected. Next: ./dqx.sh play  (first run downloads ~31 GB)."
  else
    warn "Did not find DQXBoot.exe afterward — did the installer use the default path?"
    warn "Expected: $DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe"
  fi
}

cmd_play() {
  require_proton
  local boot="$DQX_PREFIX/$GAME_REL/Boot"
  [ -f "$boot/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."
  cd "$boot"
  # WINEPATH puts the Game\ dir on Wine's exe search path so the launcher can
  # spawn DQXGame.exe (which it launches by bare name after login).
  export WINEPATH="$GAME_WIN_GAMEDIR"
  # Keep the desktop awake during play (set DQX_INHIBIT=0 to disable).
  : "${DQX_INHIBIT:=1}"; export DQX_INHIBIT
  msg "Launching DQX. First run downloads/patches (~31 GB) via the in-game updater."
  msg "Tip: a transient 'DQ-10009 / can't connect' right after the first boot update"
  msg "     is harmless — just run ./dqx.sh play again."
  umu_run DQXBoot.exe
}

case "${1:-}" in
  doctor)  cmd_doctor ;;
  setup)   cmd_setup ;;
  install) shift; cmd_install "$@" ;;
  play)    cmd_play ;;
  ""|-h|--help|help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown command: $1  (try: doctor | setup | install | play)" ;;
esac
