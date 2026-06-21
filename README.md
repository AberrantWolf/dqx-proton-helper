# dqx-proton-helper

Helper scripts to run **Dragon Quest X Online (Japanese client)** on Linux with
**Proton**, outside of Steam and Lutris. They create a Proton prefix, run *your
own* copy of the official DQX installer into it, and launch the game with the few
non-obvious settings that make it work end-to-end (gameplay + the launcher movie
+ in-game FMV cutscenes).

> **This does not download or provide the game.** You need your own DQX installer
> and an active Square Enix account. See **[Getting the game](#getting-the-game)**.

---

## Status / what's actually verified

- ✅ **Verified working** on **CachyOS** with **`proton-cachyos-11`** (Wine 11): full
  install → patch download → login → gameplay, launcher movie, and in-game FMV (via
  the 思い出プロジェクター / memory projector).
- 🟡 **Expected to work** on **GE-Proton ≥ 10-34**: the specific client crash that this
  setup avoids was confirmed absent there with new-WoW64, but the *full* flow was not
  run on it. Please report back.
- ❌ **Plain Wine is not supported.** The game client crashes (null-pointer deref)
  without Proton's **new-WoW64** mode, and there's no equivalent lever in vanilla Wine.

If you get it working on another Proton build, a PR/issue noting the build + result
is welcome.

## Prerequisites

- A Linux box with a working Vulkan GPU driver.
- **[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)** (`umu-run` on PATH).
- A **Proton build with new-WoW64**: **GE-Proton ≥ 10-34** or **proton-cachyos**,
  placed in a Steam `compatibilitytools.d/` directory (or point `PROTONPATH` at it).
- The **`ja_JP.utf8`** locale generated on your system.
- **Your own DQX "All-In-One" installer** (`Setup.exe`) — see below.
- An active **Square Enix account** with DQX registered.
- ~**35 GB+** free disk.

Run `./dqx.sh doctor` to check the first three.

## Getting the game

This repo deliberately covers only the *prefix + launcher* side. For obtaining and
registering the game (installer, account, region, payment), use the community guides:

- Adventurer's Abbey — getting started: <https://dqxabbey.com/pages/getting_started.html>
- DQX Translation Project FAQ: <https://dqx-translation-project.github.io/faq/faq/>
- The **"DQX on Steam Deck / Linux / WINE"** thread in the DQX community Discord.

## Usage

```sh
./dqx.sh doctor                    # check prerequisites
./dqx.sh setup                     # create a clean Proton prefix
./dqx.sh install ~/Downloads/Setup.exe   # run YOUR installer; install to the DEFAULT path
./dqx.sh play                      # first run downloads/patches ~31 GB; then log in
```

First `play` will sit on the updater for a while (tens of minutes) while it pulls the
full game. After that, `./dqx.sh play` goes straight to the launcher → login.

### Configuration (environment variables)

| Variable     | Default              | Meaning                                   |
|--------------|----------------------|-------------------------------------------|
| `DQX_PREFIX` | `~/Games/dqx-prefix` | Where the Proton prefix lives             |
| `PROTONPATH` | auto-detected        | Path to the Proton build to use           |

## Why these specific settings (the hard-won bits)

- **`PROTON_USE_WOW64=1` (new-WoW64)** — without it the game client (`DQXGame.exe`)
  crashes on launch with a null-pointer deref. This is *the* reason plain Wine won't do.
- **`WINEPATH=…\DRAGON QUEST X\Game`** — after login the launcher starts `DQXGame.exe`
  by bare name; without the Game directory on the search path you get `ErrorCode = 2`.
- **Fresh install, not a copied tree** — the launcher's content-update step deadlocks if
  you drop a pre-existing/complete game tree into the prefix. Let the in-game updater
  download into the prefix it lives in. (These scripts do that by default.)
- **Japanese locale** — the client needs `ja_JP.utf8`.
- **No LAV Filters / WebView2 / wmp needed** — the launcher movie and in-game FMVs
  (WMV3) decode through Proton's bundled GStreamer (`avdec_wmv3`). Don't bother installing
  codec packs.

## Known issues / tips

- **Sleeping during controller play.** On Wayland, gamepad input does **not** reset the
  desktop idle timer, so the screen can blank / the machine can suspend mid-game. `play`
  holds a `systemd-inhibit --what=idle:sleep` lock for the game's lifetime to prevent this
  (disable with `DQX_INHIBIT=0`). If your screen *still* blanks under KDE, your
  screen-energy-saving may need the freedesktop ScreenSaver inhibition instead — open an
  issue and we'll add it.
- **`DQ-10009` "could not connect to the internet"** right after the first boot
  self-update is a transient transition glitch — just `./dqx.sh play` again. (Real
  connectivity is fine; the boot update already succeeded.)
- **Black rectangles** in the launcher are a cosmetic GDI redraw issue, not a failure.
- The launcher may spawn a brief **"already running"** popup — dismiss it.

## License

Public domain — see [UNLICENSE](UNLICENSE). No warranty of any kind; use at your own
risk. Not affiliated with or endorsed by Square Enix. "Dragon Quest" is a trademark of
its respective owner.
