# Wine X11 managed first-map reproducer

This standalone Win32 program reproduces the black pre-launch health-and-safety
window seen in DQX without requiring the game, its assets, or an account.

The program deliberately follows the important part of the launcher's behavior:

1. Create a 640x480 popup window.
2. Call `ShowWindow()` and `UpdateWindow()` so `WM_PAINT` runs synchronously.
3. Paint an unmistakable blue, gray, and white test image.
4. Sleep for three seconds without pumping another message.

On Windows the painted image remains visible. On the affected Wine X11 path,
the managed window is black for its entire lifetime. Wine's GDI trace shows the
paint and window-surface flush completing, but the first upload occurs before
the window manager has mapped the X11 window. The upload is lost when the
window becomes viewable, and the sleeping application does not process the
later expose event.

The failure was reproduced on Ubuntu 24.04 under Mutter with an unmodified Wine
master build at commit `e3bb4552d761ce6a310321eb2d8fdb8fa6c46cbb`. Captures
taken immediately, after 400 ms, and after another second were all completely
black.

## Build

Install Debian/Ubuntu package `gcc-mingw-w64-i686`, then run:

```sh
i686-w64-mingw32-gcc -O2 -Wall -Wextra -Werror \
  -municode -mwindows -static -Wl,--no-insert-timestamp \
  -o dqx-first-map-repro.exe dqx-first-map-repro.c
```

The prebuilt 32-bit executable is included for convenience.

## Run

```sh
wine dqx-first-map-repro.exe
```

Expected result on an affected configuration: a black 640x480 window appears
for three seconds, despite the program having synchronously painted its client
area.

For a focused trace:

```sh
WINEDEBUG=-all,+timestamp,+win,+bitblt wine dqx-first-map-repro.exe \
  >dqx-first-map-repro.log 2>&1
```

The practical DQX workaround is a per-application `Managed=N` Wine X11 setting.
Making this reproducer unmanaged likewise avoids the managed-map race, but that
is a compatibility workaround rather than a general Wine fix.

The source and executable are public domain under the repository's UNLICENSE.
