# Binary Pack Release Assets

The source repository should stay reviewable: scripts, source, patches, build
recipes, and documentation only. Generated Windows helpers and CrossOver binary
deltas belong in a separate release asset.

Recommended release asset name:

```text
dqx-wine-helper-macos-crossover-26.2-binpack-vYYYYMMDD.zip
```

Recommended contents:

```text
manifest.json
bin/dqx-launcher-clip.exe
repro/dqx-first-map-repro.exe
patches/crossover-26.2/binary-deltas/*.bsdiff
```

`manifest.json` records SHA-256 for every payload file. For CrossOver deltas,
it should also record the target CrossOver version, the exact stock input hash,
and the expected patched output hash. The installer/helper must verify all of
that before using a file from the pack.

Do not put full CodeWeavers modules in a binpack. If binary deltas are included,
they must be reproducible from the source patches/build scripts and guarded by
exact input/output hashes.

Make one binpack per CrossOver target version. A 26.2 binpack must never contain
or advertise deltas for 26.3, and the helper should refuse to apply a delta
unless the user's stock module hash exactly matches the manifest.

Maintainer flow:

1. Build helper executables or deltas locally.
2. Copy them under `build/binpack-input/` using their final paths, for example
   `build/binpack-input/bin/dqx-launcher-clip.exe`.
3. Run `./packaging/make-binpack.sh`.
4. Upload the generated zip from `build/binpack-release/` to a GitHub Release.
5. Publish the zip SHA-256 in the release notes.

User flow:

```sh
./dqx.sh fetch-binpack
```

Manual/offline user flow:

```sh
DQX_BINPACK_SHA256=<zip sha256 from release notes> \
  ./dqx.sh binpack /path/to/dqx-wine-helper-macos-crossover-26.2-binpack.zip
```

The helper extracts the pack into `vendor/binpack/`, refuses full CrossOver
modules, and then uses files from there during `doctor`, `setup`, and `play`.
