# DQX on macOS (Apple Silicon, CrossOver)

Running the Japanese DQX client on Apple Silicon through CrossOver. This is now
scripted by `./dqx.sh` for the parts we can safely automate: bottle setup,
IPAMona font download/install, font aliases, installer launch, durable GStreamer/WINEPATH
configuration, launch, and hash verification of the known patched modules. Anything marked
*(unverified)* is a working theory, not fact.

Quick path:

```sh
./dqx.sh doctor
./dqx.sh fetch-binpack
./dqx.sh setup
./dqx.sh install /path/to/Setup.exe
./dqx.sh play
```

The `fetch-binpack` step is the no-build-environment path for normal users. It downloads
two pinned release assets:

- `dqx-wine-helper-win32-binpack-v20260701.zip`, installed to `vendor/binpack/win32/`.
- `dqx-wine-helper-macos-crossover-26.2-patches-v20260701.zip`, installed to
  `vendor/binpack/macos-crossover-26.2/`.

The first contains small Win32 helper executables such as `bin/dqx-launcher-clip.exe`. The
second contains exact-hash `.bsdiff` deltas for the CrossOver 26.2 modules.

## Stack

- **CrossOver 26.2** (`26.2p0.7.1`, build `26.2.0.39821`) — Wine 11.0 base, x86_64 under
  Rosetta 2, new-WoW64 (32-bit PE guest + 64-bit Unix host). DQX is 32-bit, so it loads the
  **i386-windows** PE DLLs.
- Bottle: `~/Library/Application Support/CrossOver/Bottles/DQX`.
- Render path in the clean 2026-07-01 setup: stock CrossOver D3D path. No dgVoodoo2 or
  CXPatcher graphics wrapper was required to reach the online menu.
- Movies use CrossOver's Wine media path plus the official macOS GStreamer framework for
  missing codecs. The bottle sets `GST_PLUGIN_PATH` to the framework plugin directory.

## Resume checklist

Current minimal state:

- `/Applications/CrossOver.app` is the active target, not the old debug copy.
- Patched `win32u.so` hash:
  `761e3f607c7814de5aa88b9c07b0b7368ead3acd27d62ff0e5031bddc84ad45d`.
- Patched PE `winegstreamer.dll` hash:
  `605caa4af8a159ef0a5aa258e06d7680b22f57b610095c4988e6a87914b1491a`.
- Source-built, ad-hoc-signed native `winegstreamer.so` hash:
  `8680c71a1991d51eebabe3132e127557877e7e35c6d0420ca767276c0b5250ad`.
  The unsigned local build hash was
  `015e9fabfca6afc6f751d9f32bb4daada644eb79dda9707e37185a3df8db8185`.
- No `libvulkan.1.dylib` symlink, dgVoodoo2 files, or CXPatcher graphics changes were needed
  for the clean launcher/game test.

## Solved

### Launcher / H&S / updater rendering

Current best minimal macOS launcher stack, verified on 2026-07-01 with a clean
`/Applications/CrossOver.app` 26.2 restore and the real `DQX` bottle:

- Rebuilt CrossOver 26.2.0 `win32u.so` from CodeWeavers' own source tarball
  (`~/dqx-wine-debug/crossover-sources-26.2.0.tar.gz`) with the H&S surface hook in
  `dlls/win32u/window.c`.
- The rebuild **must** keep FreeType enabled. The earlier rebuilt `win32u.so` broke launcher
  text and font metrics because it was configured `--without-freetype`; CrossOver's stock
  `win32u.so` dynamically loads its bundled x86_64 FreeType.
- Active module:
  `/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/win32u.so`
  (`sha256 761e3f607c7814de5aa88b9c07b0b7368ead3acd27d62ff0e5031bddc84ad45d`).
- No separate H&S helper overlay is needed with the patched `win32u.so`.
- The existing one-shot `dqx-launcher-clip.exe` helper fixes the updater progress bar
  rendering. In source checkouts this comes from the optional release binpack at
  `vendor/binpack/bin/dqx-launcher-clip.exe`. No CXPatcher or dgVoodoo files were present
  for the clean startup/updater test.
- Known cosmetic issue: while updater mode is active, the BGM ON/OFF icon can appear to show
  OFF even when `launcher.ini` has `PlayBGM=1` and music is audible. Likely cause, not yet
  independently verified: the progress helper's temporary parent `WS_CLIPCHILDREN` style may
  clip a parent-painted ON overlay and leave a child/base OFF-looking icon visible.

Observed good sequence with the above:

1. Initial DQXBoot splash appears without the oversized white border after the font aliases
   are corrected.
2. H&S `ご注意` warning appears.
3. Main launcher stays open.
4. Left-side player/radio labels render again.

The `win32u` hook that makes H&S visible is intentionally small: after
`pWindowPosChanged()`, when a top-level, newly shown, splash-sized surface exists, it sends
`WM_PRINT` to visible child windows and flushes the parent surface. This matches the Ubuntu
finding that the DQX H&S child/static bitmap is drawn before Wine/macOS has a presentable
native surface. In CrossOver macdrv the child exists and has the bitmap, but the early child
paint is otherwise not presented.

The exact FreeType-enabled build shape used for `win32u.so`:

```sh
BASE="$HOME/dqx-wine-debug"
SRCW="$BASE/sources/wine"
BLD="$BASE/build-win32u-cxft"
CX="$BASE/CrossOver-dbg.app/Contents/SharedSupport/CrossOver"
export PATH="/opt/homebrew/opt/bison/bin:$PATH"
export FREETYPE_CFLAGS="-I$BASE/sources/freetype/include"
export FREETYPE_LIBS="-L$CX/lib64 -lfreetype"
"$SRCW/configure" \
  --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
  --enable-archs=x86_64 \
  --with-mingw --without-x --with-freetype --without-gstreamer --disable-tests \
  CFLAGS="-g -O2 -arch x86_64" \
  LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../../../lib64"
make -j"$(sysctl -n hw.ncpu)" dlls/win32u/win32u.so
```

### FMV / movies — verified, full playback with audio

Root cause was a **Wine 11.0 WMA-DMO bug** in winegstreamer's `wma_decoder.c`:
`media_object_ProcessOutput` didn't clear `buffers[0].dwStatus` on
`MF_E_TRANSFORM_NEED_MORE_INPUT`, so `DMO_OUTPUT_DATA_BUFFERF_INCOMPLETE` stayed set and the
DMO wrapper's drain loop busy-spun `ProcessOutput` millions of times — audio died and the
video froze ~5.8 s in. Fixed by backporting the Wine 11.11 one-liner:

```c
buffers[0].dwStatus = 0;  /* clear stale INCOMPLETE so the DMO drain loop terminates */
```

into the **i386 PE** `winegstreamer.dll`. See [MOVIES.md](MOVIES.md) for the cross-platform
pipeline; an Ubuntu vanilla Wine 11.11 capture (healthy — 273 `ProcessInput` / 2428
`ProcessOutput`, single thread) confirmed the same path works once the fix is present (11.11
has it upstream).

- Applied to `/Applications/CrossOver.app/.../lib/wine/i386-windows/winegstreamer.dll`
  (`sha256 605caa4af8a159ef0a5aa258e06d7680b22f57b610095c4988e6a87914b1491a`).
- CrossOver's bundled GStreamer lacks the libav codecs DQX's WMV/WMA path needs. The clean
  setup uses the official `/Library/Frameworks/GStreamer.framework` package and sets
  `GST_PLUGIN_PATH` in `cxbottle.conf` so CrossOver discovers `avdec_wmv3` and `avdec_wmav2`.
- The native `winegstreamer.so` also needs rpaths that can load the framework libraries. We
  first validated CXPatcher's CodeWeavers-signed bridge, then rebuilt the module ourselves
  from CrossOver 26.2 Wine source with the same framework rpaths. The verified live,
  ad-hoc-signed source-built module hash is
  `8680c71a1991d51eebabe3132e127557877e7e35c6d0420ca767276c0b5250ad`.
- **Durability caveat:** a CrossOver update overwrites these modules. `./dqx.sh`
  can verify hashes and can copy locally supplied patch artifacts from
  `patches/crossover-26.2/artifacts/`, but this repository must not redistribute CodeWeavers
  binaries.

### Fonts — IPAMona helps, but the aliases must be exact

On macOS/CrossOver, do not make users find winetricks. The helper downloads the whole
IPAMona package from FreeBSD's `japanese/font-mona-ipa` port distcache, verifies the
FreeBSD-pinned SHA-256, installs the five TTF files into `~/Library/Fonts`, then applies
the CrossOver registry aliases.

Package:

```text
opfc-ModuleHP-1.1.1_withIPAMonaFonts-1.0.8.tar.gz
SHA256 ab77beea3b051abf606cd8cd3badf6cb24141ef145c60f508fcfef1e3852bb9d
```

The FreeBSD port marks the package as `NOTPARTIAL`: free redistribution of the whole
package is allowed, but not partial redistribution. This repo does not redistribute the
fonts; it downloads the complete package for the user and installs from that verified
local copy.

The first conclusion here was too optimistic. A native `CreateFont` probe in the DQX
CrossOver bottle showed that, after removing broken test aliases, the MS Gothic family names
resolve to Arial-like 16 px metrics at 96 DPI. The IPAMona faces installed in
`~/Library/Fonts` resolve to the expected 13 px metrics, matching the Linux DQXConfig
research.

The working alias set is now captured in `macos-fix-dqx-fonts.sh`:

- `MS UI Gothic` -> `Ume UI Gothic` (CrossOver's Japanese Font Override face)
- `MS Shell Dlg` -> metric-compatible UI Gothic
- `MS Gothic` / `ＭＳ ゴシック` -> `IPAMonaGothic`
- `MS PGothic` / `ＭＳ Ｐゴシック` -> `IPAMonaPGothic`
- Mincho names -> the matching IPAMona Mincho faces

Do **not** map Gothic UI requests to Mincho. Also do **not** remove CrossOver's
`MS UI Gothic -> Ume UI Gothic` mapping in a clean bottle: on 2026-07-01 that made
`DQXBoot` resolve `MS UI Gothic` through a taller Hiragino fallback, growing the
startup splash window from about `632x481` to `722x558` and leaving the visible
white border around the 640x480 bitmap. Restoring `MS UI Gothic -> Ume UI Gothic`
returned the splash to the baseline size while keeping DQXConfig at `656x496`.

The older bad test state had
`MS UI Gothic -> IPAMonaMincho` and `MS PGothic -> IPAMonaPMincho`, which made some launcher
text disappear and left dialog metrics wrong.

Previous findings that still seem useful:

- Every launcher/boot/config binary (`DQXBoot`, `DQXUpdater`, `DQXLauncher`, `DQXConfigMini`,
  `DQXConfig`, `DQXProfiler`) requests only **MS UI Gothic** and **MS Shell Dlg** (+ Latin
  Tahoma/Segoe UI). `DQXGame.exe`/`DQXTitle.exe` embed no GDI font names — in-game text uses
  the game's own font system.
- The modern names — **Meiryo, Meiryo UI, Yu Gothic** — all fall back to *Adobe Fan Heiti
  Std B* (a Chinese font, too tall, ASCII rendered double-wide). A real bug, but DQX never
  asks for them, so it doesn't bite.
- `Meiryo -> MS UI Gothic` did not help this bottle, so avoid broad modern-font aliases.

## Open

- **Flicker (active).** Whole draw calls / chunks of geometry drop out on cel-outlined
  character and NPC meshes — not the terrain pass, not texture flicker, not z-fighting, and
  not shader compilation (the HUD never shows "compiling" when it happens). Worse with more
  characters on screen, persistent, random per-frame. Removing the MVK arg-buffers env var
  (above) didn't fix it. Working theory *(unverified)*: dynamic vertex-buffer / submission
  sync under load. Next experiment, not yet applied: `dxgi.maxFrameLatency = 1`.
- **Make the CrossOver patches fully turnkey.** Binary deltas are generated and supported
  by the helper, but the split release assets still need to be uploaded and pinned before
  fresh users can run the whole path without local artifacts.
- **CodeWeavers bug report.** The H&S behavior is still worth reporting. Minimal repro:
  DQX's `DQXLauncher.exe` creates a splash-sized parent surface and a visible 640x480
  child/static `SS_BITMAP` H&S control; the child bitmap is present but is not shown unless
  a post-surface child `WM_PRINT` + parent flush is forced in `win32u`.
- **DQXConfig buttons**. Fixed by the exact IPAMona/Ume aliases; keep a clean-run font probe
  in the release checklist.
- **Launcher missing text**. Now fixed in the 2026-07-01 clean CrossOver test. If it regresses,
  first check that active `win32u.so` was built with FreeType and that the bad Mincho aliases
  have not returned.
- **Stutters.** In-game stutter warms out after 10–15 min (Rosetta AOT + shader cache). The
  movie's early stutters repeat in the same spots; still to confirm they're that same Rosetta
  AOT warmup rather than decode.

## New CrossOver versions

Treat every CrossOver update as a new port, not as a hash bump. CrossOver updates can change
the Wine base, bundled GStreamer, macdrv behavior, module paths, signatures, and rpaths.

Recommended maintainer flow:

1. Install the new CrossOver into a separate app bundle first, for example
   `/Applications/CrossOver-26.3.app`, and keep the last known-good app around.
2. Run a completely stock smoke test with a fresh or copied test bottle:
   `./dqx.sh doctor`, `setup`, `install`, and `play` with `CX_APP` pointed at
   the new app bundle.
3. Verify the three fixes independently:
   - Launcher startup: DQXBoot splash has no oversized white border, H&S appears, launcher
     reaches the normal/updater UI.
   - Updater redraw: progress bar repaints without dragging/moving the window.
   - Movies: title/movie playback reaches video and audio without black-screen freeze.
4. If a fix is no longer needed, remove it for that CrossOver version instead of carrying it
   forward. In particular, the WMA-DMO `dwStatus` fix is upstream in newer Wine and may
   disappear once CodeWeavers rebases past it.
5. If a fix is still needed, rebuild from the new CrossOver source release, never by copying
   the old patched module. Re-apply the smallest source patch, preserve the new build's
   FreeType/GStreamer/rpath shape, ad-hoc sign locally, and record fresh stock/patched
   SHA-256 hashes.
6. Create a new patch directory such as `patches/crossover-26.3/`. Do not overwrite
   `patches/crossover-26.2/`; old users still need the old hashes.
7. Generate new binary deltas only from the exact verified stock modules for that CrossOver
   version, and publish them only in a versioned optional binpack release asset.
8. Update the macOS CrossOver platform module only after the new version is verified. Ideally it should
   select patch metadata by detected CrossOver build rather than letting a 26.2 delta apply
   to anything else.

If a new CrossOver version fails in a new way, first rerun the window/module diagnostics from
`RESEARCH-NOTES.md` before changing the setup script. A clean failure note is better than
quietly widening a workaround.

## Remaining Work

- Upload and pin the split win32 and macOS/CrossOver 26.2 binpack release assets.
- Add reproducible build scripts for the three patched CrossOver modules.
- Report the H&S redraw issue and the `winegstreamer` `dwStatus` fix to CodeWeavers.
- Keep testing graphics/performance regressions from the clean minimal baseline.

## Diagnostics notes

- CrossOver detaches plain stderr for bottle apps — even via `wine --cx-app` from the CLI —
  so `WINEDEBUG=+font` (and friends) can come back empty. Use CrossOver's wrapper flags
  instead: `--debugmsg '+resource,+macdrv,...' --cx-log /tmp/trace.log`. The capture driver
  exposes these as `CX_DEBUGMSG` and `CX_LOG`.
- Window capture for headless inspection: find the `CGWindowID` via a small Swift
  `CGWindowListCopyWindowInfo` dump, then `screencapture -o -x -l <id>`.
