# dqx-proton-helper

Helper scripts to run **Dragon Quest X Online (Japanese client)** on Linux with
**Proton** (outside of Steam or Lutris). They create a Proton prefix, run your copy
of the DQX installer into it, and launch the game with the few non-obvious settings
that make it work correctly (gameplay + the launcher movie + in-game FMV cutscenes).

> **This does not download or provide the game.** You need your own DQX installer
> and an active Square Enix account. Other guides have that information (see
> **[Getting the game](#getting-the-game)**).

---

## Status

- ✅ **Verified working** on **CachyOS** with **`proton-cachyos-11`** (based on Wine 11):
  full install → patch download → login → gameplay, launcher movie, and in-game FMV (via
  the おもいで映写機 / memory projector).
- 🟡 **Probably works** on **GE-Proton ≥ 10-34**: I tried at least some of the launcher
  setup, and this will enable the "new-WoW64" path via Proton args, but I didn't verify if
  any cutscenes played, nor did I actually log in. So if you run it, please report back.
- ❌ **Plain Wine is not supported.** The game client crashes (null-pointer deref)
  without Proton's **new-WoW64** mode, it seems, and there's maybe no equivalent option in
  vanilla Wine.

If you get it working on another Proton build, a PR/issue noting the build + result is
welcome. This is just something I spent way too long vibing out with Claude Code over a
couple days, so I'm not precious about it.

## Prerequisites

- A Linux box with a working Vulkan GPU driver.
- **[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)** (`umu-run` on PATH).
- A **Proton build with new-WoW64**: **GE-Proton ≥ 10-34** or **proton-cachyos**,
  placed in a Steam `compatibilitytools.d/` directory (or point `PROTONPATH` at it). (on
  my machine, this was just already installed, so I can't help you if yours doesn't have
  something like this... maybe it's not even needed?)
- The **`ja_JP.utf8`** locale generated on your system. This makes it so that more of the
  install dialogs and system dialogs come up with something other than gibberish or empty
  squares.
- **Your DQX "All-In-One" installer** (`Setup.exe`) — see below.
- An active **Square Enix account** with DQX registered.
- ~**35 GB+** free disk.

(Run `./dqx.sh doctor` to check the first three.)

## Getting the game

This repo deliberately covers only the *prefix + launcher* side. For obtaining and
registering the game (installer, account, region, payment), use the community guides:

- Adventurer's Abbey — getting started: <https://dqxabbey.com/pages/getting_started.html>
- DQX Translation Project FAQ: <https://dqx-translation-project.github.io/faq/faq/>
- The **"DQX on Steam Deck / Linux / WINE"** thread in the DQX community Discord.

> I get my installer through the purchase history page on the Square Enix store, since
> that's how I bought the game. But the installer comes from various places as I
> understand it.

## Usage

```sh
./dqx.sh doctor                    # check prerequisites
./dqx.sh setup                     # create a clean Proton prefix
./dqx.sh install your/path/to/Setup.exe   # run your installer; install to the DEFAULT path
./dqx.sh play                      # first run downloads/patches ~31 GB; then log in
```

> When installing the game, pick the default location, otherwise the launch helper
> script won't find it.

Thf first time you run with `play`, the launcher drops into updater mode, which is normal.
It's downloading like 27GiB of data or something, as is the way with MMOs, so let it sit
for a while. After that, `./dqx.sh play` goes to the launcher where you can login.

### Configuration (environment variables)

You can customize tom paths if needed. But the defaults are probably fine.

| Variable     | Default              | Meaning                                   |
|--------------|----------------------|-------------------------------------------|
| `DQX_PREFIX` | `~/Games/dqx-prefix` | Where the Proton prefix lives             |
| `PROTONPATH` | auto-detected        | Path to the Proton build to use           |

## What Does the Helper Customize?

- **`PROTON_USE_WOW64=1` (new-WoW64)** — without it the game client (`DQXGame.exe`)
  crashes on launch with a null-pointer deref. This seems to be *the* reason plain Wine
  won't do. Happy to be wrong if you try it, though.
- **`WINEPATH=…\DRAGON QUEST X\Game`** — after login the launcher starts `DQXGame.exe`
  by bare name; without the Game directory on the search path you get `ErrorCode = 2`
  and the launcher claims your install is corrupted (which it probably isn't).
- **Japanese locale** — the client needs `ja_JP.utf8`, otherwise the pre-game (especially
  config tool) text is even more unreadable than if you can't read Japanese.

## What I Ended Up NOT Needing
- **LAV Filters / WebView2 / wmp** — the launcher movie and in-game FMVs (WMV3) decode
  through Proton's bundled GStreamer (`avdec_wmv3`). Don't bother installing codec packs.

## Known issues / tips

- **Sleeping during controller play.** On Wayland, gamepad input does **not** reset the
  desktop idle timer, so the screen can blank / the machine can suspend mid-game. `play`
  holds a `systemd-inhibit --what=idle:sleep` lock for the game's lifetime to prevent this
  (disable with `DQX_INHIBIT=0`). If your screen *still* blanks under KDE, your
  screen-energy-saving may need the freedesktop ScreenSaver inhibition instead — open an
  issue and we'll add it.
- **`DQ-10009` "could not connect to the internet"** right after the first boot
  self-update is a transient transition glitch I saw once — just run `./dqx.sh play` again.
  (Real connectivity is probably fine.)
- **Black rectangles** in the launcher are a cosmetic GDI redraw issue. It sucks, but I'm
  fairly sure they don't have any effect on the game itself. It's just weirdness with Wine
  versus how Windows apps can assume they work.
- If the launcher spawns a brief **"already running"** popup, you may need to reinstall
  your game. This happened when I was copying pre-installed assets between prefixes, and
  the only fix that worked was to completely reinstall the whole game in the prefix.

## License

Public domain — see [UNLICENSE](UNLICENSE). No warranty of any kind; use at your own
risk. Not affiliated with or endorsed by Square Enix. "Dragon Quest" is a trademark of
its respective owner.
