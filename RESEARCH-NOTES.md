# Research Process Notes

These notes summarize the inspection techniques used while debugging DQX under
CrossOver on macOS. The useful pattern is to look at the same event from both
sides of the boundary:

- macOS sees native processes, Mach-O dylibs, CG windows, and app bundles.
- Wine sees PE processes, PE DLLs, Win32 windows, controls, styles, fonts, and
  registry state.
- CrossOver's wrapper sits between them and can silently set environment,
  library paths, GStreamer paths, and bottle configuration.

## Process And Library State

### `ps`, `pgrep`, and process command lines

Use these first to see which Wine-side executable is actually alive:

```sh
ps aux | rg -i 'DQX|wine|CrossOver|wineserver|gstreamer|gst'
pgrep -if 'dqxTitle.exe|DQXGame.exe|DQXLauncher.exe'
```

This distinguishes launcher, title movie, and game handoff states. For example,
`dqxTitle.exe` running with a `【タイトルムービー】` window means the launcher did
start the movie process; a missing `DQXGame.exe` can be expected if the user
returned to the launcher.

### `lsof -p <pid>`

`lsof` shows files a process has opened or mapped. This was the quickest way to
answer "did this process load the library/plugin we expected?"

```sh
pid=$(pgrep -if 'dqxTitle.exe' | head -n1)
lsof -p "$pid" | rg -i 'winegstreamer|quartz|wmv|wma|gst|libav'
```

Important examples:

- `.../i386-windows/winegstreamer.dll`: the 32-bit PE Wine bridge loaded by the
  32-bit Windows process.
- `.../x86_64-unix/winegstreamer.so`: the native Unix/Mach-O side loaded by
  Wine's host process.
- `/Library/Frameworks/GStreamer.framework/.../libgstlibav.dylib`: the GStreamer
  libav plugin, needed for `avdec_wmv3` / `avdec_wmav2`.
- `libavcodec.*.dylib`, `libavformat.*.dylib`, `libavutil.*.dylib`: FFmpeg
  dependencies used after the libav plugin is active.

`lsof` is excellent for yes/no questions but can get noisy during plugin scans.

### `vmmap <pid>`

`vmmap` gives a native memory map and confirms mapped Mach-O images, including
Rosetta AOT images:

```sh
vmmap "$pid" | rg -i 'winegstreamer|gstreamer|gst|libav|quartz'
```

This is useful when `lsof` output is ambiguous or when you want to verify which
side of a universal binary was actually mapped. On Apple Silicon, CrossOver's
x86_64 code under Rosetta often also maps `/private/var/db/oah/.../*.aot`.

### `sample <pid> <seconds>`

`sample` takes a native stack sample. It is useful for "is it busy or waiting?"
questions:

```sh
sample "$pid" 2 -file /tmp/dqx-title-sample.txt
rg -i 'winegstreamer|gst|quartz|wait|semaphore|decoder|dmo' /tmp/dqx-title-sample.txt
```

If stacks are mostly in `NtWaitForSingleObject`,
`NtUserMsgWaitForMultipleObjectsEx`, or macOS semaphore waits, the process may be
idle, blocked, or waiting for media/presentation work rather than crashing.

## Binary And Bundle Inspection

### `file`

Use `file` to check architecture before copying plugins:

```sh
file /Applications/CrossOver.app/.../libgstreamer-1.0.0.dylib
file /Library/Frameworks/GStreamer.framework/.../libgstlibav.dylib
file /opt/homebrew/.../libgstlibav.dylib
```

This mattered because CrossOver on Apple Silicon is running x86_64 under Rosetta.
Homebrew under `/opt/homebrew` was arm64-only and not usable for CrossOver's
x86_64 GStreamer path. The official `/Library/Frameworks/GStreamer.framework`
package was universal and did include x86_64.

### `otool -L` and `otool -l`

`otool -L` shows dynamic dependencies and ABI compatibility versions:

```sh
otool -L /Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstlibav.dylib
otool -L /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/winegstreamer.so
```

This exposed an important distinction:

- CrossOver's bundled GStreamer core was `1.24.5`.
- The installed official framework was `1.28.4`.
- Dropping only a newer `libgstlibav.dylib` into CrossOver's old plugin directory
  would not be safe because the plugin links against newer GStreamer ABI.

`otool -l` shows load commands such as `LC_RPATH`:

```sh
otool -l winegstreamer.so | awk '/LC_RPATH/{show=1; next} show && /path /{print; show=0}'
```

This showed why the CXPatcher `winegstreamer.so` mattered during research: it
had rpaths pointing at `/Library/Frameworks/GStreamer.framework/Libraries`,
letting Wine use the framework's native GStreamer libraries. We later reproduced
that behavior from CrossOver 26.2 Wine source with a source-built
`winegstreamer.so`.

### `strings`

`strings` is crude but useful for wrapper behavior and binary breadcrumbs:

```sh
strings -a /Users/scott/Downloads/CXPatcher.app/Contents/MacOS/CXPatcher |
  rg -i 'gstreamer|libav|gst|framework|download'
```

This revealed that CXPatcher has a GStreamer patch path, references the official
GStreamer macOS package URL, and knows about CrossOver's `winegstreamer.so`.

### `codesign -dv`

Use this to distinguish stock CodeWeavers-signed binaries from local rebuilt or
ad-hoc signed ones:

```sh
codesign -dv --verbose=2 /Applications/CrossOver.app/.../win32u.so
codesign -dv --verbose=2 /Users/scott/Downloads/CXPatcher.app/.../winegstreamer.so
```

Code signing also changes file hashes, so compare hashes before and after
signing with that in mind.

### `shasum`

Hash every binary before and after replacing it:

```sh
shasum -a 256 source.dll live.dll backup.dll
```

This kept the minimal-change work honest: stock `winegstreamer.dll`, patched
`winegstreamer.dll`, stock `win32u.so`, and patched `win32u.so` were all
identifiable by hash.

## CrossOver Wrapper And Bottle Configuration

CrossOver's `bin/wine` is not plain Wine. It is a Perl wrapper that:

- resolves the bottle;
- reads `cxbottle.conf`;
- sets library and DLL paths;
- sets GStreamer plugin paths;
- applies `--env` or `CX_ENV`;
- launches the real Wine loader.

Useful places:

```sh
/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine
~/Library/Application Support/CrossOver/Bottles/DQX/cxbottle.conf
```

The wrapper has this relevant behavior:

```text
[EnvironmentVariables] in cxbottle.conf
  -> applied by CXBottle::set_environment()

GST_PLUGIN_SYSTEM_PATH
  -> forced to CrossOver's bundled lib64/gstreamer-1.0 when present

GST_REGISTRY
  -> stored in ~/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin
```

The durable way to add bottle-local variables is:

```ini
[EnvironmentVariables]
"GST_PLUGIN_PATH" = "/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0"
"WINEPATH" = "C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game"
```

Using `--env` is fine for one-off tests, but CrossOver accepts only one `--env`
argument and applies it late. For repeatable configuration, prefer
`cxbottle.conf`.

After changing GStreamer paths, move the registry aside so it rescans:

```sh
mv "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin" \
   "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin.before-test"
```

Then inspect the rebuilt registry:

```sh
strings -a "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin" |
  rg -i 'libgstlibav|avdec_wmv3|avdec_wmav2'
```

## GStreamer Inspection

The official framework provides `gst-inspect-1.0`. On Apple Silicon, force
x86_64 to match CrossOver:

```sh
arch -x86_64 /Library/Frameworks/GStreamer.framework/Versions/1.0/bin/gst-inspect-1.0 avdec_wmv3
arch -x86_64 /Library/Frameworks/GStreamer.framework/Versions/1.0/bin/gst-inspect-1.0 avdec_wmav2
```

The factories we needed were:

- `avdec_wmv3`: Windows Media Video 9 decoder, sink caps `video/x-wmv,
  wmvversion=3, format=WMV3`.
- `avdec_wmav2`: Windows Media Audio 2 decoder, sink caps `audio/x-wma,
  wmaversion=2`.

The important distinction:

- `GST_PLUGIN_SYSTEM_PATH` came from CrossOver and pointed only at the small
  bundled plugin set.
- `GST_PLUGIN_PATH` was needed to add the official framework plugin directory.
- The native `winegstreamer.so` rpaths make the framework GStreamer dylibs
  loadable, but do not by themselves make the framework plugin directory
  searchable. CXPatcher's bridge proved the idea; the current validated setup
  uses a source-built bridge with equivalent framework rpaths.

## macOS Window Inspection

### CoreGraphics window list

macOS exposes visible windows through CoreGraphics:

- `CGWindowListCopyWindowInfo`
- `CGWindowListCreateImage` (called via a Swift `_silgen_name` declaration
  because it is not always directly imported)

The key metadata:

- `kCGWindowOwnerName`: native owner name, such as `DQXLauncher.exe`.
- `kCGWindowName`: title, such as `ドラゴンクエストＸ　オンライン`.
- `kCGWindowNumber`: `CGWindowID`, useful for capture.
- `kCGWindowBounds`: screen-space geometry.
- `kCGWindowLayer`: normal app windows are usually layer `0`.
- `kCGWindowAlpha`: useful for hidden/fading windows.

Early helpers:

```sh
swiftc tools/cg-window-sampler.swift -o build/cg-window-sampler
swiftc tools/cg-window-capture.swift -o build/cg-window-capture

./build/cg-window-sampler 5 0.05
./build/cg-window-capture <window-id> /tmp/window.png
```

The productized helper now lives at:

```sh
/Users/scott/Programming/window-burst
```

Example:

```sh
/Users/scott/Programming/window-burst/.build/release/window-burst \
  8 0.02 /tmp/dqx-capture \
  --owner DQX --owner Wine --owner CrossOver --title 'ドラゴンクエスト' --min-width 300
```

It writes PNG frames and `manifest.tsv`. This is how we caught the half-second
startup splash and measured the font-regression geometry:

- baseline DQXBoot splash: about `632x481/479`;
- bad `MS UI Gothic` fallback splash: about `722x558`;
- H&S splash: `640x480`;
- launcher: `800x600`;
- game/title windows: `1280x748`.

macOS may require Screen Recording permission for the terminal or agent process.

### `screencapture -l`

For quick one-off capture when you already have a `CGWindowID`:

```sh
screencapture -o -x -l <window-id> /tmp/window.png
```

The Swift/CoreGraphics helper was more reliable for burst captures.

## Win32 Window And Control Inspection

macOS window APIs see native toplevel windows, but they do not show Win32 child
controls. For that, run a small Windows executable inside the bottle.

`tools/window-dump.c` uses:

- `EnumWindows` / `EnumChildWindows`;
- `GetClassNameW`, `GetWindowTextW`;
- `GetWindowLongPtrW(GWL_STYLE/GWL_EXSTYLE)`;
- `GetWindowRect`;
- `SendMessageTimeoutW` so a hung control does not hang the probe;
- listbox messages such as `LB_GETCOUNT`, `LB_GETTEXT`, `LB_GETITEMDATA`;
- `ReadProcessMemory` for owner-drawn listbox item data.

This reveals things macOS cannot see:

- child control classes such as `Static`, `Button`, `msctls_progress32`;
- whether a child control is visible;
- styles such as `SS_BITMAP`, `WS_VISIBLE`, `WS_CLIPCHILDREN`;
- listbox item text/data;
- child geometry inside the parent client area.

This was central to the H&S and updater work: the bitmap/control existed on the
Win32 side even when macOS showed a black/blank surface.

The updater progress workaround `dqx-launcher-clip.exe` uses the same family of
Win32 APIs:

- `FindWindowW("DQXLauncher.MainWindow", NULL)`;
- `FindWindowExW(..., "msctls_progress32", ...)`;
- `GetWindowLongPtrW` / `SetWindowLongPtrW`;
- `WS_CLIPCHILDREN`.

## Windows Module Inspection

`tools/module-dump.c` runs inside Wine and uses Toolhelp:

- `CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS)`;
- `CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)`;
- `Module32FirstW` / `Module32NextW`.

This answers "which PE DLLs does the Windows process think it loaded?"

That is different from `lsof`/`vmmap`, which answer "which native Mach-O dylibs
did the host process map?" For Wine media debugging both views matter:

- PE side: `quartz.dll`, `wmvcore.dll`, `wmadmod.dll`, `winegstreamer.dll`.
- native side: `winegstreamer.so`, GStreamer dylibs, FFmpeg/libav dylibs.

## Font And DPI Inspection

`tools/font-probe.c` creates real GDI fonts and measures what Wine resolves:

- `CreateFontIndirectW`;
- `SelectObject`;
- `GetTextFaceW`;
- `GetTextMetricsW`;
- `GetDeviceCaps(LOGPIXELSY)`.

This let us prove that DQXConfig's layout issue was font metrics, not DPI alone,
and later that removing `MS UI Gothic -> Ume UI Gothic` made DQXBoot's startup
splash grow a white border.

Useful output shape:

```text
request=MS UI Gothic h=-13 -> face=MS UI Gothic tmHeight=13 ...
request=ＭＳ ゴシック h=-13 -> face=ＭＳ ゴシック tmHeight=13 ...
```

## Wine And CrossOver Logging

Plain stderr is often not enough with CrossOver because GUI bottle apps detach
from the launching terminal. Prefer CrossOver wrapper options:

```sh
/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine \
  --bottle DQX \
  --debugmsg '+winegstreamer,+gstreamer,+quartz,+mfplat' \
  --cx-log /tmp/dqx-media.log \
  ...
```

Useful Wine channels varied by task:

- `+winegstreamer,+gstreamer,+quartz,+mfplat` for media.
- `+font` for font selection, when the build emits it.
- `+resource` for dialog resources.
- `+macdrv` for macOS driver/window behavior.

Not every CrossOver build logs all channels you might expect, especially around
fonts, so native probes were often more reliable than traces.

## Registry And Bottle State

Use CrossOver's `wine reg` to inspect or change Wine registry keys:

```sh
cx=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine
"$cx" --bottle DQX reg query 'HKCU\Software\Wine\Fonts\Replacements'
"$cx" --bottle DQX reg add 'HKCU\Software\Wine\Fonts\Replacements' \
  /v 'MS UI Gothic' /t REG_SZ /d 'Ume UI Gothic' /f
```

For durable font changes, `macos-fix-dqx-fonts.sh` writes the relevant registry
values. For durable CrossOver environment variables, use `cxbottle.conf` as
described above.

## Debugging Pattern

The most useful workflow was:

1. Confirm process state with `ps`/`pgrep`.
2. Capture native windows with `window-burst`.
3. If the native window exists but is wrong, inspect Win32 children/styles with
   `window-dump.exe`.
4. If media is involved, check the PE DLL side with `module-dump.exe`, then the
   native dylib/plugin side with `lsof`/`vmmap`.
5. Check dynamic linking with `file`, `otool -L`, and `otool -l`.
6. Check CrossOver wrapper behavior and `cxbottle.conf`; do not assume plain Wine
   environment semantics.
7. Make one change, clear caches/registries if needed, then retest with the same
   capture/probe sequence.

The important mental model: Wine is not one process boundary. DQX can load a
32-bit PE DLL, that DLL can call into a 64-bit native Unix library, that native
library can load macOS framework dylibs, and the final visual result can be a
CoreGraphics window. Each tool observes a different layer of that stack.
