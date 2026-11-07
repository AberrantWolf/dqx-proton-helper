#!/usr/bin/env bash

# Copy only the pack's known files. Stage them on the destination filesystem
# before replacing any installed files, and serialize writes to this directory.
install_binpack_files() (
  local source="$1" dest="$2" stage path parent
  shift 2
  case "$dest" in /*) ;; *) dest="$PWD/$dest" ;; esac
  mkdir -p "$dest"
  stage="$dest/.dqx-binpack.lock"
  mkdir "$stage" || die "Cannot stage binpack in $dest (another install may be in progress)"
  trap 'rm -rf "$stage"' EXIT

  for path in "$@"; do
    [ -e "$source/$path" ] || [ -L "$source/$path" ] || continue
    [ -f "$source/$path" ] && [ ! -L "$source/$path" ] \
      || die "Invalid binpack file: $path"
    parent="$(dirname "$path")"
    while [ "$parent" != . ]; do
      [ ! -L "$source/$parent" ] && [ ! -L "$dest/$parent" ] \
        || die "Refusing binpack directory symlink: $parent"
      parent="$(dirname "$parent")"
    done
    [ ! -L "$dest/$path" ] && { [ ! -e "$dest/$path" ] || [ -f "$dest/$path" ]; } \
      || die "Cannot replace binpack file: $dest/$path"
    mkdir -p "$stage/$(dirname "$path")" "$dest/$(dirname "$path")"
    cp -p "$source/$path" "$stage/$path"
  done

  for path in "$@"; do
    if [ -f "$stage/$path" ]; then
      mv -f "$stage/$path" "$dest/$path"
    fi
  done
)

install_win32_binpack() {
  install_binpack_files "$1" "$2" bin/dqx-launcher-clip.exe \
    repro/dqx-first-map-repro.exe manifest.json
}
