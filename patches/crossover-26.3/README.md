# CrossOver 26.3 Movie Patches

Target build `26.3.0.39832` on Apple Silicon. The two modules were tested on
DQX 8.1 with the official universal GStreamer 1.28.4 framework. The stock
`win32u.so` displayed the health-and-safety screen.

Build from the [CodeWeavers 26.3 source archive](https://www.codeweavers.com/crossover/source).
In the extracted `sources/wine` directory, apply the existing
[WMA status patch](../crossover-26.2/source/winegstreamer-wma-dwstatus.patch)
with `patch -p1`. It applies to 26.3 as-is. The native bridge uses the
framework at link time and adds its library directory as a runtime search path.

From an out-of-tree build directory, set `WINE_SRC` to the absolute path to
that patched `sources/wine` directory. The build used Homebrew's Bison, MinGW
and GStreamer 1.28.5 headers, with the universal 1.28.4 framework libraries.

```sh
export PATH="/opt/homebrew/opt/bison/bin:$PATH"
export GSTREAMER_CFLAGS="$(pkg-config --cflags gstreamer-1.0 gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-tag-1.0)"
export GSTREAMER_LIBS='-L/Library/Frameworks/GStreamer.framework/Libraries -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0 -lgmodule-2.0'
"$WINE_SRC/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
  --enable-archs=i386,x86_64 --with-mingw --with-gstreamer --without-x \
  --without-freetype --disable-tests 'CFLAGS=-g -O2 -fno-omit-frame-pointer -arch x86_64' \
  'LDFLAGS=-arch x86_64 -Wl,-rpath,/Library/Frameworks/GStreamer.framework/Libraries'
make -j8 dlls/winegstreamer/winegstreamer.so dlls/winegstreamer/i386-windows/winegstreamer.dll
codesign --force --sign - dlls/winegstreamer/winegstreamer.so
```

Use the exact stock and tested output hashes in
[`platform/macos-crossover.sh`](../../platform/macos-crossover.sh) to generate
the deltas. A rebuild can produce different hashes, so verify playback and
update the pins if the binaries change. For each module, run `bsdiff` on the
stock and patched files, then use `bspatch` and `cmp` to verify the delta
recreates the tested output.

From the repository root, put the two deltas under
`build/binpack-macos-26.3-input/patches/crossover-26.3/binary-deltas/`
with names `winegstreamer.dll.bsdiff` and `winegstreamer.so.bsdiff`, then run:

```sh
BINPACK_NAME=dqx-wine-helper-macos-crossover-26.3-patches-v20261107 \
  BINPACK_INPUT="$PWD/build/binpack-macos-26.3-input" \
  BINPACK_TARGET_CROSSOVER=26.3.0.39832 ./packaging/make-binpack.sh
./packaging/make-release.sh
```

The user release includes the delta pack. Keep full modules in the ignored
[local artifacts directory](artifacts/).
