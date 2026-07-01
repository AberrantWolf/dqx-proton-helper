# Local Patch Artifacts

This directory is a local-only drop zone for patched CrossOver modules.

`./dqx.sh patches` on macOS/CrossOver looks here by default for:

- `win32u.so`
- `winegstreamer.dll`
- `winegstreamer.so`

The helper verifies each file by SHA-256 before installing it, backs up the
current CrossOver module, and ad-hoc signs the replacement.

Do not commit module binaries in this directory. Keep only this README.
