# dqx-proton-helper

Helper scripts for running **Dragon Quest X Online (Japanese client)** on Linux. The
default path uses plain **Wine** (no Steam or Lutris), creates and provisions a Wine
prefix, runs your copy of the DQX installer, and launches the game with the few
non-obvious settings needed for gameplay, the launcher's HTML UI, and FMV playback.
Plain Wine 11.11 is verified on CachyOS and Ubuntu 24.04; `GE-Proton11-1` through
`umu` remains an optional fallback.

> Yeah, the repo's called `dqx-proton-helper`. It started out using Proton through
> umu, and the name stuck. The default path is now plain Wine on both tested systems.

> **This does not download or provide the game.** You need your own DQX installer
> and an active Square Enix account. Other guides have that information (see
> **[Getting the game](#getting-the-game)**).

---

## Status

Known-good baseline: plain **Wine 11.11** on both CachyOS and Ubuntu 24.04.

On CachyOS, the full install, ~30 GB patch download, launcher, trial quick-play,
gameplay, and in-game FMV through the おもいで映写機 / memory projector all run.

On Ubuntu 24.04 with NVIDIA 595, WineHQ Staging `wine-11.11` was verified using
`WINEARCH=wow64` with an existing fully installed 64-bit prefix. The launcher,
`DQXTitle.exe` handoff, complete title movie with audio, login, menus, and movement
all worked through WineD3D and host GStreamer. No Proton, DXVK, or borrowed Steam
app ID was active. The memory-projector FMV was not repeated during this Ubuntu test.

The captured movie pipeline, runtime differences, and cross-platform diagnostic
checklist are documented in [MOVIES.md](MOVIES.md).

The hard requirement is **active new-WoW64 execution**, not merely the presence of a
`wow64.dll` file:

- Pure-new-WoW64 distro builds, such as the tested CachyOS package, have no i386 Unix
  loader and use the new path with a normal `WINEARCH=win64` prefix.
- Dual/multilib WineHQ 11 builds, including Ubuntu 24.04 packages, also contain the old
  i386 Unix path. They must use `WINEARCH=wow64` to force the tested new path.

Earlier Ubuntu failures used `WINEARCH=win64`, which selected old WoW64 on the
multilib WineHQ installation. A pure `WINEARCH=win32` prefix was also tested, but
that is not equivalent to new WoW64. The helper now detects the selected Wine layout,
chooses the correct mode automatically, and reports it in `./dqx.sh doctor`.

Alternative paths remain available: `GE-Proton11-1` through `umu` works with
`PROTON_USE_WOW64=1`, and wine-cachyos `10.0-20260425` works but may need the
explicit `DQX_MOVIE_COMPAT_GAMEID=638160` WMReader workaround. Neither is the
default.

If you get it working on another distro or Wine version, a PR/issue noting it is welcome.
This is just something I spent way too long vibing out with Claude Code over a couple
days, so I'm not precious about it.

## Prerequisites

- A Linux box with working GPU drivers. The game is DirectX 9 and renders through
  WineD3D → OpenGL by default; DXVK/Vulkan remains optional for performance experiments.
- **Wine 11.11 or newer** is recommended. Both pure-new-WoW64 distro builds and WineHQ
  multilib builds work when the correct mode is active. Selected downstream Wine 10 builds
  may work, but are not the primary baseline.
- **winetricks** — used to install the Japanese IPAMona fonts.
- For plain Wine, **GStreamer + gst-libav** provide the launcher movie and in-game FMV
  decoding. You need `asfdemux`, `avdec_wmv3`, `avdec_wmav2`, and the normal conversion
  elements. GE-Proton11's optional fallback uses its own Wine DMO/FFmpeg path instead.
- The **`ja_JP.UTF-8`** locale generated on your system. This makes more installer and
  system dialogs render as Japanese instead of gibberish or empty squares.
- On NVIDIA, a working matching host driver is required. New WoW64 loads the 64-bit Unix
  OpenGL stack, so the old-mode requirement for a separate i386 Wine/OpenGL path does not
  apply to the default setup.
- **Your DQX installer** — the "All-In-One" `Setup.exe`, or the trial's
  `DQXInstaller_ft.exe`.
- An active **Square Enix account** with DQX registered.
- ~**35 GB+** free disk (the client download alone is ~30 GB).

Run `./dqx.sh doctor` to check the selected Wine layout and active mode, fonts, Gecko,
plain-Wine media/graphics dependencies, and the optional GE-Proton11/umu fallback.

## Getting the game

This repo deliberately covers only the *prefix + launcher* side. For obtaining and
registering the game (installer, account, region, payment), use the community guides:

- Adventurer's Abbey — getting started: <https://dqxabbey.com/pages/getting_started.html>
- DQX Translation Project FAQ: <https://dqx-translation-project.github.io/faq/faq/>
- The **"DQX on Steam Deck / Linux / WINE"** thread in the DQX community Discord.

> I get my installer through the purchase history page on the Square Enix store, since
> that's how I bought the game. But the installer comes from various places as I
> understand it.

## Doing it by hand

If you'd rather not run a random shell script — or you just want to know what it's
actually doing — here's the whole thing by hand. The script is just these steps with
some checks bolted on. Swap in your own paths.

1. **Make a 64-bit prefix using the new-WoW64 mode.** For WineHQ 11 multilib
   packages, export `wow64` explicitly:
   ```sh
   export WINEPREFIX="$HOME/Games/dqx-prefix"
   export WINEARCH=wow64
   wineboot --init
   ```
   On a pure-new-WoW64 distro build with no i386 Unix loader, use
   `export WINEARCH=win64` instead. Keep that value for the later Wine commands.
   The helper's `DQX_WINEARCH=auto` selection handles this distinction for you.

2. **Let Wine install Gecko.** The launcher's news/UI panels are HTML, rendered by Wine's
   MSHTML, which needs Wine-Gecko — without it you get the launcher's images but no text.
   When you make the prefix (or first launch something that uses it) Wine pops up a dialog
   offering to download Gecko; say yes. (You can skip the Mono/.NET one — DQX doesn't use
   it.) If it never offers, grab the `wine-gecko-<ver>-x86.msi` matching your Wine version
   from <https://dl.winehq.org/wine/wine-gecko/> and `wine msiexec /i` it.

3. **Drop in Japanese fonts.** Use IPAMona — it's metric-compatible with the old MS Gothic
   / MS PGothic the game's dialogs were drawn for, so things line up instead of overlapping
   or stretching. (Other CJK fonts render the text fine but mangle the dialog layout.)
   ```sh
   winetricks -q fakejapanese_ipamona
   ```

4. **Turn on TLS 1.2**, or the Square Enix launcher just refuses to connect:
   ```sh
   wine reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' \
     /v SecureProtocols /t REG_DWORD /d 0xA80 /f
   ```

5. **Run your installer.** Install to the default location. The installer is
   Japanese-only — the `LC_ALL` is what makes it readable instead of gibberish:
   ```sh
   LC_ALL=ja_JP.UTF-8 wine /path/to/Setup.exe
   ```

6. **Launch the game.** Run `DQXBoot.exe` from its own `Boot` directory, with the `Game`
   directory on Wine's exe search path — after login the launcher starts `DQXGame.exe` by
   bare name, and without that it can't find it (you get `ErrorCode = 2` and a bogus
   "your install is corrupted"):
   ```sh
   cd "$WINEPREFIX/drive_c/Program Files (x86)/SquareEnix/DRAGON QUEST X/Boot"
   LC_ALL=ja_JP.UTF-8 \
     WINEPATH='C:\Program Files (x86)\SquareEnix\DRAGON QUEST X\Game' \
     wine DQXBoot.exe
   ```
   First run drops into the updater and pulls ~30 GB. Let it sit.

## ...or just use the script

Same steps, automated, with prerequisite checks:

```sh
./dqx.sh doctor                          # verify Wine mode and prerequisites
./dqx.sh setup                           # make the prefix: Gecko + IPAMona + TLS
./dqx.sh install /path/to/Setup.exe      # run your installer (give it the real path)
./dqx.sh play                            # recommended: plain Wine
# fallback: ./dqx.sh play-umu            # GE-Proton11 through umu
```

> When installing the game, pick the default location, otherwise the launch helper
> script won't find it.

The first time you run `play`, the launcher drops into updater mode, which is normal.
It's downloading like 27GiB of data or something, as is the way with MMOs, so let it sit
for a while. After that, `./dqx.sh play` goes to the launcher where you can log in.

### Configuration (environment variables)

You can customize some paths if needed. But the defaults are probably fine.

| Variable | Default | Meaning |
|----------|---------|---------|
| `DQX_PREFIX` | `~/Games/dqx-prefix` | Where the Wine prefix lives |
| `WINE` | `wine` | Which Wine binary to use |
| `DQX_LOCALE` | `ja_JP.utf8` | Japanese locale to run under |
| `DQX_WINEARCH` | `auto` | Detect pure versus dual WoW64; override with `win64` or `wow64` |
| `DQX_JP_FONT` | IPAMona | Override with a host Japanese font family |
| `DQX_INHIBIT` | `1` | Hold an idle/sleep lock while playing (`0` disables) |
| `DQX_MOVIE_COMPAT_GAMEID` | disabled | Set `638160` only for an affected wine-cachyos 10.0 WMReader path |
| `DQX_UMU` | `umu-run` | UMU launcher binary for fallback `play-umu` |
| `DQX_PROTONPATH` | auto-detect `GE-Proton11-1` | Override GE-Proton path for `play-umu` |
| `DQX_UMU_GAMEID` | `dqx` | UMU `GAMEID` for `play-umu`; not a Steam app ID |

## What you don't need

- **Steam, Lutris, Proton, or umu.** Plain Wine is the verified default on both
  tested systems. GE-Proton11/umu is retained only as a fallback.
- **Codec packs / LAV Filters / WebView2 / wmp.** Plain Wine decodes DQX's WMV media
  through host GStreamer/`gst-libav`; GE-Proton11 uses its Wine DMO/FFmpeg path.
  You *do* need Gecko for plain Wine's MSHTML launcher UI, which is separate from
  WebView2 and movie decoding.

## Known issues / tips

- **Sleeping / screen-locking during play.** On Wayland, gamepad input does **not** reset
  the desktop idle timer, so the screen can blank/lock or the machine can suspend mid-game.
  `play` holds a wake lock for the game's lifetime to prevent this: `systemd-inhibit
  --what=idle:sleep` (suspend + idle), plus — on KDE — `kde-inhibit --power --screenSaver`
  so the Plasma screen locker and blanking are covered too (the logind idle lock alone
  doesn't reliably stop KDE's locker). Disable all of it with `DQX_INHIBIT=0`.
- **Controller moves your desktop cursor (KDE).** If your gamepad's left stick drags the
  mouse pointer around the desktop, that's KDE's **"Game Controller Desktop Mode"**, not the
  game — turn it off in System Settings (search "controller"). Heads up: that feature also
  doubles as keeping the session awake while a controller's in use, but `play` holds its own
  wake lock (above), so disabling it won't let DQX sleep.
- **`DQ-10009` "could not connect to the internet"** right after the first boot
  self-update is a transient transition glitch I saw once — just run `./dqx.sh play` again.
  (Real connectivity is probably fine.)
- **`DQXTitle.exe` crashes before the title movie loads.** Do not start it directly;
  the launcher passes required startup state. First run `./dqx.sh doctor`. On a dual/multilib
  WineHQ installation, `WINEARCH=win64` selects old WoW64 and reproduced the early
  `012645AF` access violation before `quartz`, `winegstreamer`, or `d3d9` loaded.
  `DQX_WINEARCH=auto` now selects `wow64`, which passed the same handoff on Ubuntu.
  Codec changes cannot fix the pre-media signature.
- **A movie opens as a blank or transparent window under wine-cachyos 10.0.** The affected
  WMReader path can expose compressed WMV3 samples to D3D9. Retry explicitly with
  `DQX_MOVIE_COMPAT_GAMEID=638160 ./dqx.sh play`. This borrows another game's downstream
  compatibility behavior, so it is deliberately disabled by default and is not needed by
  the verified WineHQ 11.11 path.
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
