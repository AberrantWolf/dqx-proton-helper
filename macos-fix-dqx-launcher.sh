#!/usr/bin/env bash
#
# Keep DQXLauncher.exe/H&S off launcher-hostile render paths.
#
# On the macOS CrossOver path we keep dgVoodoo's D3D9.dll in Game/ for the 3D
# client, and sometimes in Boot/ for DQXTitle/movie experiments. DQXLauncher.exe
# also lives in Boot/ and imports d3d9. Keep only the launcher on CrossOver's
# builtin d3d9 so Boot-local render experiments do not leak into launcher/H&S.
#
# Older experiments installed a Boot-local gdiplus.dll proxy. The minimal font
# fix is now in macos-fix-dqx-fonts.sh: leave MS UI Gothic unaliased. This script
# disables that old proxy state if it is present.

set -euo pipefail

: "${CX_ROOT:=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
: "${CX_BOTTLE:=DQX}"
: "${DQX_INSTALL_DIR:=}"

wine_bin="$CX_ROOT/bin/wine"

[ -x "$wine_bin" ] || {
  printf 'CrossOver wine not found: %s\n' "$wine_bin" >&2
  exit 1
}

bottle_dir="$HOME/Library/Application Support/CrossOver/Bottles/$CX_BOTTLE"
if [ -n "$DQX_INSTALL_DIR" ]; then
  dqx_dir="$DQX_INSTALL_DIR"
else
  dqx_dir="$bottle_dir/drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X"
fi
boot_dir="$dqx_dir/Boot"

[ -d "$boot_dir" ] || {
  printf 'DQX Boot directory not found: %s\n' "$boot_dir" >&2
  exit 1
}
launcher_overrides='HKCU\Software\Wine\AppDefaults\DQXLauncher.exe\DllOverrides'

reg_add_launcher() {
  "$wine_bin" --bottle "$CX_BOTTLE" reg add \
    "$launcher_overrides" \
    /v "$1" /t REG_SZ /d "$2" /f >/dev/null
}

reg_delete_launcher() {
  "$wine_bin" --bottle "$CX_BOTTLE" reg delete \
    "$launcher_overrides" /v "$1" /f >/dev/null 2>&1 || true
}

disable_old_proxy_file() {
  local dll="$1" disabled="$1.disabled-by-dqx-helper"
  [ -f "$dll" ] || return 0
  [ -f "$disabled" ] && disabled="$disabled.$(date +%Y%m%d-%H%M%S)"
  mv "$dll" "$disabled"
}

reg_add_launcher d3d9 builtin
reg_delete_launcher gdiplus
"$wine_bin" --bottle "$CX_BOTTLE" reg delete \
  'HKLM\System\CurrentControlSet\Control\Session Manager\KnownDLLs' \
  /v gdiplus /f >/dev/null 2>&1 || true

disable_old_proxy_file "$boot_dir/gdiplus.dll"
disable_old_proxy_file "$boot_dir/gdiplus_real.dll"

printf 'DQXLauncher.exe now uses builtin d3d9 in CrossOver bottle %s.\n' "$CX_BOTTLE"
printf 'Disabled old launcher-local GDI+ proxy files if they were present.\n'
printf 'Removed DQXLauncher.exe gdiplus override and stale KnownDLLs entry if present.\n'
printf 'DQXGame.exe and DQXTitle.exe are not changed.\n'
