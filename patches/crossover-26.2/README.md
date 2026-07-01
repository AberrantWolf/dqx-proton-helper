# CrossOver 26.2 Patch Set

This directory is the single home for the macOS CrossOver 26.2 patch material.

It is intentionally split by purpose:

- `source/` contains human-readable source patches and patch notes for Wine-side
  changes.
- `build/` contains scripts or notes for reproducing patched modules from the
  CrossOver 26.2 source release.
- `binary-deltas/` is reserved for generated `bsdiff` patches from verified
  stock CrossOver modules to verified patched modules.
- `artifacts/` is a local-only drop zone for patched modules produced by a build
  script or supplied by the user.

Do not commit full CrossOver modules, app bundles, or other proprietary
CodeWeavers binaries. The checked-in source should be enough to audit what we
change and to reproduce the local patch artifacts.

See `../../LICENSES.md` for the repository-wide licensing notes.

## Porting To A New CrossOver Version

Do not reuse these patched modules, binary deltas, or hashes for another
CrossOver release. This directory is specific to CrossOver 26.2.

For a new CrossOver version:

1. Make a sibling directory, for example `patches/crossover-26.3/`.
2. Capture the new stock module paths, CodeWeavers build number, and SHA-256
   hashes before changing anything.
3. Test stock CrossOver first. Some local fixes may have landed upstream or
   become unnecessary after a Wine/GStreamer/macdrv rebase.
4. Re-apply source patches to the new CrossOver source tree only where the bug
   still reproduces. Keep patches small and Wine-side.
5. Rebuild modules from the new version's source release and preserve that
   version's dependency/rpath/signing shape.
6. Record fresh patched SHA-256 hashes and update the helper only after the
   module is tested against DQX startup, updater, launcher, and movie playback.
7. Generate new `.bsdiff` files from exact new stock hashes to exact new
   patched hashes. Never apply a delta across CrossOver versions.
8. Publish any deltas through a versioned binpack release asset, not as full
   modules and not as loose binaries in git.

When in doubt, leave the new version unsupported until it has its own verified
patch directory and release notes. A hard stop is much easier to debug than a
misapplied binary patch.
