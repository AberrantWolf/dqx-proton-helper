# dqx-proton-helper

Helper scripts for running **Dragon Quest X Online (Japanese client)** on Linux. The
default helper path uses plain **Wine** (no Steam or Lutris), sets up a Wine prefix,
runs your copy of the DQX installer into it, and launches the game with the few
non-obvious settings that make it work (gameplay + the launcher's HTML UI + in-game
FMV cutscenes). On Ubuntu 24.04, `GE-Proton11-1` through `umu` is currently also a
known-good runtime path; see **[Status](#status)**.

> Yeah, the repo's called `dqx-proton-helper`. It started out built on Proton (via umu).
> On the CachyOS baseline, recent plain Wine is enough; on Ubuntu this repo now also
> tracks the GE-Proton/umu path because WineHQ currently trips over DQXTitle startup.
> The name stuck.

> **This does not download or provide the game.** You need your own DQX installer
> and an active Square Enix account. Other guides have that information (see
> **[Getting the game](#getting-the-game)**).

---

## Status

Known-good baseline: plain **Wine 11.11** on CachyOS. On that setup, the full install,
the ~30 GB patch download, the launcher, the trial's quick-play, and in-game FMV (via the
おもいで映写機 / memory projector) all run. No Proton, no umu — just Wine and a couple of
prefix tweaks.

Ubuntu/WineHQ status: on Ubuntu 24.04 with WineHQ devel/staging `wine-11.11` and NVIDIA 595,
`DQXTitle.exe` currently crashes before it reaches any media DLLs. That is not a
GStreamer/codec failure; see **[Known issues / tips](#known-issues--tips)** for the exact
signature. WineHQ stable `wine-11.0` is also older than the known-good baseline.
Two Ubuntu paths are now known to get past that startup crash: a local build of
`wine-cachyos` `10.0-20260425` with the helper default
`DQX_MOVIE_COMPAT_GAMEID=638160`, and `GE-Proton11-1` through `umu`/`steamrt4`
with `PROTON_USE_WOW64=1` (no 638160 app id needed). Both play the title movie
in the trial flow. Without `PROTON_USE_WOW64=1`, the GE-Proton11 launcher opens but
the movie OK button does not spawn `DQXTitle.exe`.

The one hard requirement for the default helper path is a **new-WoW64** Wine build — that's
the part that runs the 32-bit client inside the 64-bit prefix. Modern Wine (10.x, 11.x) is
built that way by default on most distros; if `./dqx.sh doctor` complains about it, that's
the thing to sort out first.

For Proton/UMU experiments, `PROTON_USE_WOW64=1` forces Proton's WoW64 path
selection. In UMU-Proton `10.0-4` that meant selecting `bin-wow64`; in `GE-Proton11-1`
it sets `WINEARCH=wow64`. That flag is not the same thing as fixing the DQXTitle startup
crash: UMU-Proton `10.0-4` still crashed before media DLLs loaded, while `GE-Proton11-1`
with the flag got through the launcher and played the title movie under `steamrt4`.

> An earlier version of this README swore you needed Proton's new-WoW64 and that plain
> Wine crashed. That was wrong — Proton was just what happened to be installed when I
> first got it going. Vanilla Wine 11 already has new-WoW64.

If you get it working on another distro or Wine version, a PR/issue noting it is welcome.
This is just something I spent way too long vibing out with Claude Code over a couple
days, so I'm not precious about it.

## Prerequisites

- A Linux box with working GPU drivers. The game is DirectX 9 and renders through wined3d
  (→ OpenGL) out of the box; DXVK/Vulkan is optional if you want to push performance.
- **Wine ≥ 10**, the new-WoW64 kind for the default helper path. The known-good baseline is
  `wine-11.11` on CachyOS; WineHQ stable `wine-11.0` is older than that. Check with
  `wine --version`.
- **winetricks** — used to drop the Japanese fonts (and, if needed, Gecko) into the prefix.
- **GStreamer + gst-libav** for the launcher movie and in-game FMV cutscenes. You need the
  ASF demuxer plus WMV3/WMA decoders (`asfdemux`, `avdec_wmv3`, `avdec_wmav2`) and the
  usual base conversion elements. Without them, movies won't decode.
- The **`ja_JP.UTF-8`** locale generated on your system. This makes it so that more of the
  install dialogs and system dialogs come up with something other than gibberish or empty
  squares.
- On NVIDIA systems, the matching **32-bit NVIDIA OpenGL package** for your driver. On
  Ubuntu this is usually `libnvidia-gl-<driver-major>:i386`, for example
  `libnvidia-gl-595:i386`. Without it, 32-bit D3D9/wined3d can fail to create a GL context.
- **Your DQX installer** — the "All-In-One" `Setup.exe`, or the trial's `DQXInstaller_ft.exe`.
- An active **Square Enix account** with DQX registered.
- ~**35 GB+** free disk (the client download alone is ~30 GB).

(Run `./dqx.sh doctor` to check Wine, winetricks, codecs, graphics, locale/fonts, and on Ubuntu the tested GE-Proton11/umu fallback path. It also tells you whether to use `play` or `play-umu`.)

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

1. **Make a 64-bit Wine prefix.**
   ```sh
   export WINEPREFIX="$HOME/Games/dqx-prefix"
   WINEARCH=win64 wineboot --init
   ```

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
./dqx.sh doctor                          # checks prerequisites and recommends a launch path
./dqx.sh setup                           # make the prefix: Gecko + IPAMona + TLS
./dqx.sh install /path/to/Setup.exe      # run your installer (give it the real path)
./dqx.sh play-umu                        # Ubuntu recommended path: GE-Proton11 via umu
# or: ./dqx.sh play                      # plain Wine path, known-good on CachyOS / wine-cachyos
```

> When installing the game, pick the default location, otherwise the launch helper
> script won't find it.

The first time you run `play`, the launcher drops into updater mode, which is normal.
It's downloading like 27GiB of data or something, as is the way with MMOs, so let it sit
for a while. After that, `./dqx.sh play` goes to the launcher where you can log in.

### Configuration (environment variables)

You can customize some paths if needed. But the defaults are probably fine.

| Variable      | Default              | Meaning                                              |
|---------------|----------------------|------------------------------------------------------|
| `DQX_PREFIX`  | `~/Games/dqx-prefix` | Where the Wine prefix lives                          |
| `WINE`        | `wine`               | Which Wine binary to use                             |
| `DQX_LOCALE`  | `ja_JP.utf8`         | Japanese locale to run under                         |
| `DQX_JP_FONT` | (IPAMona)            | Override: substitute this host font instead of IPAMona |
| `DQX_INHIBIT` | `1`                  | Hold an idle/sleep lock while playing (`0` to disable) |
| `DQX_MOVIE_COMPAT_GAMEID` | `638160` | Plain-Wine WMReader workaround for WMV3 movie playback (empty disables) |
| `DQX_UMU` | `umu-run` | UMU launcher binary for `play-umu` |
| `DQX_PROTONPATH` | auto-detect `GE-Proton11-1` | Override GE-Proton path for `play-umu` |
| `DQX_UMU_GAMEID` | `dqx` | UMU `GAMEID` for `play-umu`; not a Steam app id |

## What you don't need

- **Steam or Lutris.** The helper does not need either. Proton/umu is optional: plain
  Wine works on the tested CachyOS baseline, while Ubuntu 24.04 currently has a
  working `GE-Proton11-1`/`umu` path because WineHQ `wine-11.11` hits the
  `DQXTitle.exe` startup crash.
- **Codec packs / LAV Filters / WebView2 / wmp.** The launcher movie and in-game FMVs
  (WMV3) decode through your system GStreamer's `gst-libav`. Don't bother with codec packs.
  You *do* need Gecko, but that's MSHTML (old IE) for the launcher's HTML — a different
  thing from WebView2.

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
- **`DQXTitle.exe` crashes as soon as the title/opening movie starts.** Do not start
  `DQXTitle.exe` directly; the launcher passes it startup state. If the Wine crash details
  show only `DQXTitle.exe`, `ntdll`, `kernelbase`, and `kernel32`, and a log shows no
  `quartz`, `mfplat`, `winegstreamer`, or `d3d9` load before `c0000005`, it crashed before
  media playback. Codec packs and GStreamer changes will not fix that signature. Observed
  on Ubuntu 24.04 + WineHQ devel/staging `wine-11.11` on June 26, 2026 in both the default win64
  new-WoW64 prefix and a pure win32 trial prefix; CPU affinity limiting did not change it.
  UMU-Proton `10.0-4` reaches the launcher through Steam Runtime after allowing
  pressure-vessel's `userns` AppArmor profile, but `DQXTitle.exe` still crashes with the
  same early `012645AF` access violation before media DLLs load. `GE-Proton11-1` through
  `umu`/`steamrt4` does not show that signature and plays the title movie with
  `PROTON_USE_WOW64=1`, even with `SteamAppId=0` and `SteamGameId=0`. Without that
  flag, the launcher opens but the movie OK button does not spawn `DQXTitle.exe`.
  A local Ubuntu build of `wine-cachyos`
  `10.0-20260425` also gets past startup, but needs `DQX_MOVIE_COMPAT_GAMEID=638160`
  for movie playback. Without that Wine WMReader workaround, `DQXTitle.exe` can open a
  blank transparent movie window; logs show `WMVCore.DLL` and `winegstreamer.dll`,
  followed by `Unrecognized 0x33564d57 (as fourcc: WMV3) WINED3DFORMAT`.
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
