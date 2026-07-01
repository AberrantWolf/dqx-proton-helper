# Source Patches

Source patches for the CrossOver 26.2 Wine tree live here. Apply them from the
Wine source root with `git apply`.

Patch files:

- `win32u-dqx-hs-redraw.patch`: the small H&S child redraw / parent flush hook.
- `winegstreamer-wma-dwstatus.patch`: the WMA-DMO `dwStatus` backport from newer
  Wine.
- `winegstreamer-native-rpath-notes.md`: notes for building the native
  `winegstreamer.so` bridge with GStreamer framework rpaths.

License each patch under the same license as the Wine file it modifies, normally
Wine's LGPL terms. Do not put full CrossOver source files here; commit only the
patch/diff needed to describe our changes.
