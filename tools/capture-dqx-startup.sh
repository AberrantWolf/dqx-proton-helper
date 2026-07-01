#!/usr/bin/env bash
#
# Launch DQXBoot.exe in a CrossOver bottle and capture the short startup sequence.
# This is intentionally dumb and timestamped: DQX splash/H&S windows can live for
# less than a second, so manual screenshots miss the interesting transition.

set -euo pipefail

: "${CX_ROOT:=$HOME/dqx-wine-debug/CrossOver-dbg.app/Contents/SharedSupport/CrossOver}"
: "${CX_BOTTLE:=DQX-lab-min}"
: "${DQX_CAPTURE_TAG:=dqx-startup}"
: "${DQX_CAPTURE_SECONDS:=10}"
: "${DQX_CAPTURE_INTERVAL:=0.25}"
: "${DQX_CAPTURE_WINDOWS:=1}"
: "${DQX_CAPTURE_MODULES:=1}"
: "${DQX_CAPTURE_DESKTOP:=}"
: "${DQX_CAPTURE_CX_DESKTOP:=}"
: "${DQX_CAPTURE_APP:=DQXBoot.exe}"
: "${DQX_CAPTURE_RAW:=0}"
: "${CX_GRAPHICS_BACKEND:=dxvk}"
: "${CX_DEBUGMSG:=}"
: "${CX_LOG:=}"
: "${DQX_CAPTURE_DUMP_TIMEOUT:=3}"
: "${DQX_LAUNCHER_REDRAW_HELPER:=0}"
: "${DQX_LAUNCHER_REDRAW_READY_WAIT:=5}"

wine_bin="$CX_ROOT/bin/wine"
wineserver_bin="$CX_ROOT/bin/wineserver"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
redraw_helper="$repo_dir/build/launcher-redraw.exe"
bottle_dir="$HOME/Library/Application Support/CrossOver/Bottles/$CX_BOTTLE"
dqx_dir="$bottle_dir/drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X"
boot_dir="$dqx_dir/Boot"
game_win='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game'
boot_app="C:\\Program Files (x86)\\SquareEnix\\DRAGON QUEST X\\Boot\\$DQX_CAPTURE_APP"
out_dir="/tmp/$DQX_CAPTURE_TAG-$(date +%Y%m%d-%H%M%S)"
wine_args=(--bottle "$CX_BOTTLE")
[ -z "$CX_GRAPHICS_BACKEND" ] || wine_args+=(--env "CX_GRAPHICS_BACKEND=$CX_GRAPHICS_BACKEND")
[ -z "$DQX_CAPTURE_CX_DESKTOP" ] || wine_args+=(--desktop "$DQX_CAPTURE_CX_DESKTOP")
[ -z "$CX_DEBUGMSG" ] || wine_args+=(--debugmsg "$CX_DEBUGMSG")
[ -z "$CX_LOG" ] || wine_args+=(--cx-log "$CX_LOG")

[ -x "$wine_bin" ] || { printf 'wine not found: %s\n' "$wine_bin" >&2; exit 1; }
[ -d "$boot_dir" ] || { printf 'Boot directory not found: %s\n' "$boot_dir" >&2; exit 1; }

mkdir -p "$out_dir"

redraw_helper_pid=""
redraw_helper_log="$bottle_dir/drive_c/users/Public/dqx-launcher-redraw.log"
if [ "$DQX_LAUNCHER_REDRAW_HELPER" != 0 ]; then
  if [ -f "$redraw_helper" ]; then
    rm -f "$redraw_helper_log"
    "$wine_bin" --bottle "$CX_BOTTLE" "$redraw_helper" \
      >"$out_dir/launcher-redraw.stdout.txt" 2>&1 &
    redraw_helper_pid=$!
    for _ in $(seq 1 "$((DQX_LAUNCHER_REDRAW_READY_WAIT * 10))"); do
      [ -s "$redraw_helper_log" ] && break
      sleep 0.1
    done
  else
    printf 'launcher redraw helper not found: %s\n' "$redraw_helper" \
      >"$out_dir/launcher-redraw.stdout.txt"
  fi
fi

run_window_dump() {
  local target="$1" pid waited=0
  [ "$DQX_CAPTURE_WINDOWS" != 0 ] || return 0
  [ -f "$repo_dir/build/window-dump.exe" ] || return 0

  "$wine_bin" --bottle "$CX_BOTTLE" "$repo_dir/build/window-dump.exe" \
    >"$target" 2>&1 &
  pid=$!
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [ "$waited" -ge "$DQX_CAPTURE_DUMP_TIMEOUT" ]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      printf 'window-dump timed out after %ss\n' "$DQX_CAPTURE_DUMP_TIMEOUT" >>"$target"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" >/dev/null 2>&1 || true
}

(
  cd "$boot_dir"
  if [ -n "$DQX_CAPTURE_DESKTOP" ]; then
    env LC_ALL=ja_JP.UTF-8 WINEPATH="$game_win" \
      "$wine_bin" "${wine_args[@]}" \
      explorer "/desktop=$DQX_CAPTURE_DESKTOP" \
      "$boot_app"
  else
    if [ "$DQX_CAPTURE_RAW" != 0 ]; then
      env LC_ALL=ja_JP.UTF-8 WINEPATH="$game_win" \
        "$wine_bin" "${wine_args[@]}" \
        "$boot_app"
    else
      env LC_ALL=ja_JP.UTF-8 WINEPATH="$game_win" \
        "$wine_bin" "${wine_args[@]}" \
        --cx-app "$boot_app"
    fi
  fi
) >"$out_dir/launch.log" 2>&1 &
launch_pid=$!

count="$(awk -v d="$DQX_CAPTURE_SECONDS" -v i="$DQX_CAPTURE_INTERVAL" 'BEGIN { printf "%d", (d / i) + 1 }')"
for n in $(seq 0 "$count"); do
  stamp="$(awk -v n="$n" -v i="$DQX_CAPTURE_INTERVAL" 'BEGIN { printf "%06.2f", n * i }')"
  screencapture -x "$out_dir/screen-$stamp.png" >/dev/null 2>&1 || true
  pgrep -afil 'dqx(boot|launcher|title|game|updater|config)\.exe|wine(wrapper|server)?' \
    >"$out_dir/procs-$stamp.txt" 2>/dev/null || true
  run_window_dump "$out_dir/windows-$stamp.txt"
  sleep "$DQX_CAPTURE_INTERVAL"
done

run_window_dump "$out_dir/windows.txt"
if [ "$DQX_CAPTURE_MODULES" != 0 ] && [ -f "$repo_dir/build/module-dump.exe" ]; then
  "$wine_bin" --bottle "$CX_BOTTLE" "$repo_dir/build/module-dump.exe" \
    >"$out_dir/modules.txt" 2>&1 || true
fi

pkill -fi 'dqx(boot|launcher|title|game|updater|config)\.exe' || true
"$wineserver_bin" --bottle "$CX_BOTTLE" -k >/dev/null 2>&1 || true
wait "$launch_pid" >/dev/null 2>&1 || true
if [ -n "$redraw_helper_pid" ]; then
  wait "$redraw_helper_pid" >/dev/null 2>&1 || true
fi
[ -n "$redraw_helper_pid" ] && [ -f "$redraw_helper_log" ] && \
  cp "$redraw_helper_log" "$out_dir/launcher-redraw.log" || true

printf '%s\n' "$out_dir"
