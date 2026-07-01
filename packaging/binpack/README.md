# Binary Pack Release Assets

The source repository should stay reviewable: scripts, source, patches, build
recipes, and documentation only. Generated Windows helpers and CrossOver binary
deltas belong in a separate release asset.

Recommended release asset names:

```text
dqx-wine-helper-win32-binpack-vYYYYMMDD.zip
dqx-wine-helper-macos-crossover-26.2-patches-vYYYYMMDD.zip
```

Recommended `win32` contents:

```text
manifest.json
bin/dqx-launcher-clip.exe
repro/dqx-first-map-repro.exe
```

Recommended `macos-crossover-26.2` contents:

```text
manifest.json
patches/crossover-26.2/binary-deltas/*.bsdiff
```

`manifest.json` records SHA-256 for every payload file. For CrossOver deltas,
it should also record the target CrossOver version, the exact stock input hash,
and the expected patched output hash. The installer/helper must verify all of
that before using a file from the pack.

Do not put full CodeWeavers modules in a binpack. If binary deltas are included,
they must be reproducible from the source patches/build scripts and guarded by
exact input/output hashes.

Keep the win32 helper pack separate from platform-specific patch packs. Linux and macOS
can both use the win32 helper pack, while CrossOver deltas belong in a macOS/CrossOver
versioned pack. A 26.2 patch pack must never contain or advertise deltas for 26.3, and the
helper must refuse to apply a delta unless the user's stock module hash exactly matches the
script's expected stock hash.

Maintainer flow:

1. Build helper executables or deltas locally.
2. Copy them under an ignored input directory using their final paths, for example
   `build/binpack-win32-input/bin/dqx-launcher-clip.exe` or
   `build/binpack-macos-patches-input/patches/crossover-26.2/binary-deltas/win32u.so.bsdiff`.
3. Run `./packaging/make-binpack.sh`.
4. Upload the generated zip from `build/binpack-release/` to a GitHub Release.
5. Publish the zip SHA-256 in the release notes.

User flow:

```sh
./dqx.sh fetch-binpack
```

Manual/offline user flow:

```sh
DQX_BINPACK_SHA256=<zip sha256 from release notes> ./dqx.sh binpack /path/to/binpack.zip
```

The helper detects whether the zip is a win32 helper pack or a CrossOver patch pack,
extracts it into the matching ignored `vendor/binpack/...` directory, refuses full
CrossOver modules, and then uses files from there during `doctor`, `setup`, and `play`.
