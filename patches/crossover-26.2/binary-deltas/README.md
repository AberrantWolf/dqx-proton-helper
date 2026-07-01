# Binary Deltas

This directory is reserved for `bsdiff` patch files that transform a verified
stock CrossOver 26.2 module into a verified patched module.

The intended user flow is:

1. `macos-crossover.sh` verifies the stock module hash.
2. macOS built-in `/usr/bin/bspatch` applies the matching delta to a temporary
   file.
3. The helper verifies the patched output hash.
4. The helper backs up the original, installs the patched module, and ad-hoc
   signs it.

Do not place full module binaries here. Generated deltas should be reproducible
from the source patches/build scripts and should be guarded by exact input and
output SHA-256 hashes.
