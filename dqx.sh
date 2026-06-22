#!/usr/bin/env bash
#
# dqx.sh — Dragon Quest X Online (Japanese client) on Linux via plain Wine.
#
# A thin helper that creates a Wine prefix, runs YOUR OWN copy of the official DQX
# installer into it, and launches the game with the handful of non-obvious settings
# that make it work. It does NOT download or provide the game itself.
#
# No Proton, no umu, no Steam — just a sufficiently modern Wine. The game is a
# 32-bit DirectX 9 client; it runs through Wine's new-WoW64 mode and renders via
# wined3d (D3D9 -> OpenGL). (Tested with vanilla wine-11.11; Wine >= 10 recommended.)
#
# Public domain (Unlicense). NO WARRANTY. See README.md and UNLICENSE.
#
# Usage:
#   ./dqx.sh doctor                  # check prerequisites
#   ./dqx.sh setup                   # create + provision a clean Wine prefix
#   ./dqx.sh install /path/Setup.exe # run YOUR DQX installer into the prefix
#   ./dqx.sh play                    # launch the game
#
# Config (override via environment):
#   DQX_PREFIX   Prefix location          (default: ~/Games/dqx-prefix)
#   WINE         Wine binary to use        (default: wine)
#   DQX_LOCALE   Japanese locale to use    (default: ja_JP.utf8)
#   DQX_JP_FONT  Override: substitute the JP UI fonts with this host family instead of
#                installing IPAMona via winetricks (default: IPAMona if winetricks present)
#   DQX_INHIBIT  1=hold an idle/sleep lock while playing (default), 0=don't
set -euo pipefail

: "${DQX_PREFIX:=$HOME/Games/dqx-prefix}"
: "${WINE:=wine}"
: "${DQX_LOCALE:=ja_JP.utf8}"

GAME_REL="drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X"
GAME_WIN_GAMEDIR='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'
# Disable Mono/.NET (DQX doesn't need it) so its install prompt never appears.
# mshtml/Gecko is left ENABLED on purpose — the launcher's UI is HTML.
: "${DQX_DLLOVERRIDES:=mscoree=}"

# Japanese UI font names the DQX installer/launcher request; we point them at a
# CJK-capable font so text isn't rendered as tofu (missing-glyph boxes).
JP_FONT_NAMES=(
  "MS UI Gothic" "MS Gothic" "MS PGothic" "MS Mincho" "MS PMincho"
  "Meiryo" "Meiryo UI" "Yu Gothic" "Yu Gothic UI"
  "MS Sans Serif" "MS Shell Dlg" "MS Shell Dlg 2" "Tahoma"
)

msg()  { printf '\033[1;36m>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

# --- Wine discovery / capability probing ---------------------------------------

have_wine() { command -v "$WINE" >/dev/null 2>&1; }

# "11.11" -> prints "11 11"; empty if unparseable.
wine_version_parts() {
  "$WINE" --version 2>/dev/null | sed -nE 's/^wine-([0-9]+)\.([0-9]+).*/\1 \2/p'
}

# Candidate Wine DLL directories (for capability/Gecko-version probing).
wine_dll_dirs() {
  local b root d
  b="$(command -v "$WINE" 2>/dev/null)" || return 0
  b="$(readlink -f "$b" 2>/dev/null || printf '%s' "$b")"
  root="${b%/bin/*}"
  for d in "$root"/lib/wine "$root"/lib64/wine "$root"/lib/*/wine \
           /usr/lib/wine /usr/lib64/wine /usr/lib/*/wine /opt/wine*/lib*/wine; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done 2>/dev/null | sort -u
}

# True if this Wine ships the new-WoW64 thunk DLLs (lets a 64-bit prefix run the
# 32-bit DQX client without a 32-bit Unix Wine).
is_new_wow64() {
  local d
  for d in $(wine_dll_dirs); do
    [ -f "$d/x86_64-windows/wow64.dll" ] && return 0
    [ -f "$d/wow64.dll" ] && return 0
  done
  return 1
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
  WINEPREFIX="$DQX_PREFIX" WINEARCH=win64 LC_ALL="$DQX_LOCALE" \
  WINEDLLOVERRIDES="$DQX_DLLOVERRIDES" "$WINE" "$@"
}
reg_add() { WINEDEBUG=-all w reg add "$@" >/dev/null 2>&1; }

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
note_fail() { DOCTOR_OK=0; }

check_wine() {
  if ! have_wine; then
    warn "Wine: '$WINE' not found. Install Wine (>= 10; 11.x tested) or set WINE=/path/to/wine."
    note_fail; return
  fi
  local parts maj min
  parts="$(wine_version_parts)"
  if [ -z "$parts" ]; then
    warn "Wine: found '$WINE' but could not parse its version ($("$WINE" --version 2>/dev/null))."
  else
    read -r maj min <<<"$parts"
    if [ "$maj" -ge 11 ] 2>/dev/null; then ok "Wine: $("$WINE" --version) (>= 11, tested)"
    elif [ "$maj" -ge 10 ] 2>/dev/null; then ok "Wine: $("$WINE" --version) (>= 10, should work)"
    else warn "Wine: $("$WINE" --version) is older than 10 — new-WoW64 may be immature; untested. Upgrade recommended."; fi
  fi
  if is_new_wow64; then ok "Wine type: new-WoW64 build (can run the 32-bit client in a 64-bit prefix)"
  else warn "Wine type: could not confirm new-WoW64 (no wow64.dll found). Plain multilib Wine is untested with DQX."; fi
}

check_locale() {
  if locale -a 2>/dev/null | grep -qiE "^${DQX_LOCALE//./\\.}$|^ja_JP\.(utf8|UTF-8)$"; then
    ok "Locale '$DQX_LOCALE': present"
  else
    warn "Locale '$DQX_LOCALE': MISSING. Generate a Japanese UTF-8 locale (e.g. add 'ja_JP.UTF-8 UTF-8'"
    warn "  to /etc/locale.gen and run locale-gen, or 'localedef -i ja_JP -f UTF-8 ja_JP.UTF-8'). The JP client needs it."
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
    note_fail
  fi
}

check_gstreamer() {
  if ! command -v gst-inspect-1.0 >/dev/null 2>&1; then
    warn "GStreamer (gst-inspect-1.0) not found — the launcher movie and in-game FMV cutscenes won't play."
    warn "  Install GStreamer + gst-libav (a.k.a. gstreamer1-libav / gst-plugins-libav)."
    note_fail; return
  fi
  if gst-inspect-1.0 avdec_wmv3 >/dev/null 2>&1; then
    ok "FMV codec: gst-libav avdec_wmv3 (WMV9) present"
  else
    warn "FMV codec: gst-libav 'avdec_wmv3' MISSING — FMV cutscenes won't decode. Install gst-libav."
    note_fail
  fi
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

check_tools() {
  local t miss=0
  for t in curl; do command -v "$t" >/dev/null 2>&1 || { warn "Optional tool missing: $t (needed only to auto-download Gecko)"; miss=1; }; done
  [ "$miss" = 0 ] && ok "Helper tools: present"
}

# --- commands ------------------------------------------------------------------

cmd_doctor() {
  DOCTOR_OK=1
  check_wine
  check_locale
  check_fonts
  check_gstreamer
  check_gecko
  check_tools
  if [ -e "$DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe" ]; then ok "Game: installed at $DQX_PREFIX"
  else msg "Game: not installed yet (run 'setup' then 'install <Setup.exe>')"; fi
  echo
  [ "$DOCTOR_OK" = 1 ] && ok "Prerequisites look good." || warn "Some prerequisites are missing (see above)."
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
  # Preferred: IPAMona via winetricks. It's metric-compatible with MS PGothic / MS UI
  # Gothic (the fonts DQX's dialogs were laid out for), and installs INTO the prefix,
  # so dialogs render correctly and the setup is self-contained / portable. Other CJK
  # fonts render text fine but distort dialog layout (Noto: too big; VL Gothic: too small).
  if command -v winetricks >/dev/null 2>&1; then
    msg "Installing IPAMona Japanese fonts (winetricks fakejapanese_ipamona)..."
    # The verb aliases MS Gothic/PGothic/UI Gothic/Mincho/PMincho (+ JP-named variants).
    # Once IPAMona is a real font in the prefix, Wine's glyph fallback covers the other
    # font names (Tahoma, MS Sans Serif, MS Shell Dlg, ...), so no extra aliases are needed.
    if WINEPREFIX="$DQX_PREFIX" WINEARCH=win64 WINEDEBUG=-all \
         winetricks -q fakejapanese_ipamona >/dev/null 2>&1 && ipamona_present; then
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
  if [ -e "$DQX_PREFIX/drive_c" ]; then
    warn "Prefix already exists: $DQX_PREFIX"
    warn "Delete it (rm -rf \"$DQX_PREFIX\") or set DQX_PREFIX= to use another location."
    return 0
  fi
  mkdir -p "$DQX_PREFIX"
  msg "Creating a clean 64-bit Wine prefix at $DQX_PREFIX (this can take a minute)..."
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
    ok "Base install detected. Next: ./dqx.sh play  (first run downloads/patches the client)."
  else
    warn "Did not find DQXBoot.exe afterward — did the installer use the default path?"
    warn "Expected: $DQX_PREFIX/$GAME_REL/Boot/DQXBoot.exe"
  fi
}

cmd_play() {
  have_wine || die "Wine ('$WINE') not found."
  local boot="$DQX_PREFIX/$GAME_REL/Boot"
  [ -f "$boot/DQXBoot.exe" ] || die "Game not installed. Run setup + install first."
  # Keep the machine awake for the game's lifetime. Gamepad input does NOT reset the
  # idle timer, so without this the screen can blank/lock or the box can suspend mid-game.
  #   systemd-inhibit (logind): blocks auto-suspend + idle actions (portable).
  #   kde-inhibit (Plasma):     also blocks KDE's screen locker + blanking, which the
  #                             logind idle lock alone doesn't reliably stop on KDE.
  # Both are nested, so each applies where present. Set DQX_INHIBIT=0 to disable.
  local -a inhibit=()
  if [ "${DQX_INHIBIT:-1}" != 0 ]; then
    command -v systemd-inhibit >/dev/null 2>&1 && inhibit+=(
      systemd-inhibit --what=idle:sleep --who="Dragon Quest X"
      --why="Gameplay (controller input does not reset the idle timer)")
    command -v kde-inhibit >/dev/null 2>&1 && inhibit+=(kde-inhibit --power --screenSaver)
  fi
  msg "Launching DQX. First run drops into the updater (downloads/patches the client) — let it finish."
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
  ( cd "$boot" && \
    "${inhibit[@]}" env \
      WINEPREFIX="$DQX_PREFIX" WINEARCH=win64 LC_ALL="$DQX_LOCALE" \
      WINEDLLOVERRIDES="$DQX_DLLOVERRIDES" WINEPATH="$GAME_WIN_GAMEDIR" WINE="$WINE" \
      sh -c '"$WINE" DQXBoot.exe; sleep 5; while pgrep -f "DQX(Launcher|Game|Title|Config|Updater)\.exe" >/dev/null 2>&1; do sleep 10; done' )
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
