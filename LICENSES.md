# Licensing And Third-Party Materials

This repository's original helper scripts, probes, documentation, and small
test programs are released into the public domain under the Unlicense. See
`UNLICENSE`.

## Generated And Release Binaries

Windows `.exe` files built from this repository's source are generated artifacts,
not source files. They should not be committed loose to the repository.

- `dqx-launcher-clip.exe` is built from `dqx-launcher-clip.c`.
- `repro/first-map/dqx-first-map-repro.exe` is built from
  `repro/first-map/dqx-first-map-repro.c`.

If these are published for users who do not have a build environment, publish
them in a separate GitHub Release binary pack with a hash manifest. They are
covered by the same Unlicense terms as their source files.

Generated diagnostics binaries under `build/` are ignored and are not part of
the source distribution.

## CrossOver And Wine Patches

CrossOver is proprietary CodeWeavers software containing Wine and other
open-source components. This repository must not redistribute CrossOver app
bundles or full CodeWeavers binary modules.

Source patches under `patches/crossover-26.2/source/` are intended for the
CrossOver 26.2 Wine source tree. Each patch is offered under the same license
as the upstream file it modifies, normally Wine's LGPL terms.

Local patched modules belong in `patches/crossover-26.2/artifacts/`; that
directory is ignored except for its README. Binary deltas, when added, must be
generated only from verified stock module hashes to verified patched module
hashes and must not include full CrossOver modules.

## External Software Users Install Separately

The helper may check for or use these locally installed components, but this
repository does not redistribute them:

- CrossOver.app from CodeWeavers.
- The official macOS GStreamer framework.
- IPAMona fonts.
- Dragon Quest X installers, game data, and account assets.
- Homebrew `bsdiff`, used by maintainers to generate binary deltas.

Users are responsible for obtaining third-party software under its own license.

For IPAMona, the macOS helper downloads the complete upstream package used by
FreeBSD's `japanese/font-mona-ipa` port and verifies the FreeBSD-pinned
SHA-256 before installing the TTF files into the local user's `~/Library/Fonts`.
The FreeBSD port describes the license as allowing redistribution of the whole
package, not partial redistribution, so the repo must not commit individual
extracted font files.

## Trademarks

This project is not affiliated with or endorsed by Square Enix, CodeWeavers,
GStreamer, WineHQ, or the IPAMona font authors. Dragon Quest and related marks
belong to their respective owners.
