# Platform Helpers

`../dqx.sh` is the only user-facing entrypoint. It detects the host platform
or honors `DQX_PLATFORM` / `--platform`, then delegates to one of these modules:

- `linux.sh` — plain Wine on Linux.
- `macos-crossover.sh` — CrossOver on Apple Silicon macOS.

Keep platform-specific bottle/prefix setup, dependency checks, and launch
behavior in these modules. Shared user-facing command names should stay aligned
where possible: `doctor`, `setup`, `install`, `play`, and `fonts`.
