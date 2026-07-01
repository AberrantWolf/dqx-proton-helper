#!/usr/bin/env bash
#
# Repair DQX font aliases in a CrossOver Mac bottle.
#
# This assumes IPAMona is installed in ~/Library/Fonts and registered by
# CrossOver/Wine. Keep MS UI Gothic on CrossOver's Ume UI Gothic override:
# DQXBoot sizes its startup splash from that dialog font, while DQXConfig needs
# the MS Gothic family aliases below for metric-compatible controls.

set -euo pipefail

: "${CX_ROOT:=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
: "${CX_BOTTLE:=DQX}"

wine_bin="$CX_ROOT/bin/wine"

[ -x "$wine_bin" ] || {
  printf 'CrossOver wine not found: %s\n' "$wine_bin" >&2
  exit 1
}

for font in ipag-mona.ttf ipagp-mona.ttf ipagui-mona.ttf ipam-mona.ttf ipamp-mona.ttf; do
  [ -f "$HOME/Library/Fonts/$font" ] || {
    printf 'Missing IPAMona font: %s\n' "$HOME/Library/Fonts/$font" >&2
    exit 1
  }
done

reg_add() {
  "$wine_bin" --bottle "$CX_BOTTLE" reg add "$1" /v "$2" /t REG_SZ /d "$3" /f >/dev/null
}

reg_delete() {
  "$wine_bin" --bottle "$CX_BOTTLE" reg delete "$1" /v "$2" /f >/dev/null 2>&1 || true
}

replace_key='HKCU\Software\Wine\Fonts\Replacements'
sub_key='HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'

reg_add "$replace_key" 'MS Gothic' 'IPAMonaGothic'
reg_add "$replace_key" 'MS PGothic' 'IPAMonaPGothic'
reg_add "$replace_key" 'MS UI Gothic' 'Ume UI Gothic'
reg_add "$replace_key" '@MS UI Gothic' '@Ume UI Gothic'
reg_add "$replace_key" 'MS Mincho' 'IPAMonaMincho'
reg_add "$replace_key" 'MS PMincho' 'IPAMonaPMincho'
reg_add "$replace_key" 'MS Shell Dlg' 'IPAMonaUIGothic'
reg_add "$replace_key" 'MS Shell Dlg 2' 'Tahoma'
reg_add "$replace_key" 'Meiryo' 'IPAMonaUIGothic'
reg_add "$replace_key" 'Meiryo UI' 'IPAMonaUIGothic'
reg_add "$replace_key" 'ＭＳ ゴシック' 'IPAMonaGothic'
reg_add "$replace_key" 'ＭＳ Ｐゴシック' 'IPAMonaPGothic'
reg_add "$replace_key" 'ＭＳ 明朝' 'IPAMonaMincho'
reg_add "$replace_key" 'ＭＳ Ｐ明朝' 'IPAMonaPMincho'

reg_add "$sub_key" 'MS Gothic' 'IPAMonaGothic'
reg_add "$sub_key" 'MS PGothic' 'IPAMonaPGothic'
reg_add "$sub_key" 'MS UI Gothic' 'Ume UI Gothic'
reg_add "$sub_key" 'MS Mincho' 'IPAMonaMincho'
reg_add "$sub_key" 'MS PMincho' 'IPAMonaPMincho'
reg_add "$sub_key" 'MS Shell Dlg' 'MS UI Gothic'
reg_add "$sub_key" 'MS Shell Dlg 2' 'Tahoma'
reg_add "$sub_key" 'Meiryo' 'IPAMonaUIGothic'
reg_add "$sub_key" 'Meiryo UI' 'IPAMonaUIGothic'
reg_add "$sub_key" 'ＭＳ ゴシック' 'IPAMonaGothic'
reg_add "$sub_key" 'ＭＳ Ｐゴシック' 'IPAMonaPGothic'
reg_add "$sub_key" 'ＭＳ 明朝' 'IPAMonaMincho'
reg_add "$sub_key" 'ＭＳ Ｐ明朝' 'IPAMonaPMincho'

printf 'DQX font aliases refreshed in CrossOver bottle %s.\n' "$CX_BOTTLE"
printf 'Kept MS UI Gothic on Ume UI Gothic so DQXBoot splash sizing stays correct.\n'
printf 'Quit all Wine/CrossOver processes using the bottle before testing.\n'
