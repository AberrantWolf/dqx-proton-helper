# How DQX movies actually play under this helper

DQX's launcher movie, the opening/title movie (`DQXTitle.exe`), and in-game FMV
cutscenes (the おもいで映写機 / "memory projector") are all **WMV3 (WMV9 / VC-1
simple-main) video in ASF containers**. This doc explains how they get on screen,
because it's the single most fragile part of running DQX on Linux and the failure
modes are unintuitive.

## TL;DR

**The movies are decoded live, in place. There is no `.foz`/Theora substitution.**

There is no Proton "video converter" step here: nothing pre-transcodes the game's
WMV3 files into Theora and ships them as `transcoded_video.foz` to be swapped in at
runtime. The game's own `.wmv` assets are demuxed and decoded as-is, every frame, by
your **system GStreamer's `gst-libav` (`avdec_wmv3`)**, and the decoded frames are
handed back to the game's Direct3D 9 path.

That Proton substitution mechanism (`protonvideoconverter` + a pre-generated
`transcoded_video.foz` in the Steam shadercache) exists, but it is **not installed or
used on the default helper path** — `protonvideoconverter` isn't even registered as a
GStreamer element here, and DQX is not a Steam title in this setup. (You may see
`transcoded_video.foz` files elsewhere on the machine; those belong to *other* Proton
games' shadercaches and are unrelated.)

## The decode pipeline (default plain-Wine path)

Verified empirically by capturing a movie with
`GST_DEBUG`/`WINEDEBUG=+winegstreamer,+gstreamer,+quartz,+mfplat` on the known-good
baseline (vanilla **wine-11.11**, CachyOS, new-WoW64):

```
DQX (WMVCore / quartz / mfplat)
      │   WMReader opens the ASF, requests DECODED video samples
      ▼
winegstreamer  ──►  wg_transform (per-stream GStreamer bin)
      │                 asfdemux ─► avdec_wmv3 (gst-libav) ─► videoconvert
      ▼
decoded frames ──► Direct3D 9 (wined3d) ──► screen
```

What the capture showed for one full playthrough (intro through the main segment —
the exact spot that freezes on the macOS/CrossOver port):

- `<avdec_wmv3-1>` instantiated and decoding; `video/x-wmv … wmvversion=3,
  format=WMV3` caps negotiated at 1920×1080 then 1280×720.
- **~6000 `wg_transform_push_dmo`** sample pushes and **~27,600**
  decoded-frame reads, with buffer timestamps spanning minutes of media time —
  i.e. continuous decode, not a stall.
- **Zero** `protonvideoconverter` / `mediaconv` / Theora / `transcoded_video.foz`.
- A short burst of `Subclass refused caps` / `find_element_factories: Failed …
  video/x-wmv … WMV3` / `wg_transform_create: Failed` lines, **all within the first
  ~0.24 s**, then never again. That is Wine's normal MFT/quartz format
  *negotiation* — it brute-forces input/output type combinations, logs the misses,
  settles on the one `avdec_wmv3` accepts, and proceeds. (This matches the "bit of
  hitching at the very beginning" you see on screen.) It is **not** the freeze.

Note: `GST_DEBUG_DUMP_DOT_DIR` produces **no** `.dot` graphs here, which is expected
— winegstreamer builds anonymous per-`wg_transform` bins, not a named top-level
pipeline, so there's nothing for GStreamer to dump. The `wg_transform`/`mfplat`
traces are the real pipeline evidence instead of a `.dot`.

### Hard requirements for this path

`./dqx.sh doctor` checks for them. You need a real WMV3 decode stack in system
GStreamer:

- `asfdemux` (ASF/WMV demux) — `gst-plugins-ugly`
- `avdec_wmv3` (WMV9 video) and `avdec_wmav2` (WMA audio) — **`gst-libav`**
- `videoconvert` / `audioconvert` / `audioresample` — `gst-plugins-base`

Without `gst-libav` there is no `avdec_wmv3`, the `find_element_factories` lookup
fails *permanently* (not just during negotiation), and movies never decode. Codec
packs / LAV Filters / `wmp` / WebView2 do nothing for this; the decode is entirely on
the GStreamer side.

## The WMReader "compressed sample" trap — and `DQX_MOVIE_COMPAT_GAMEID=638160`

Having `avdec_wmv3` present is necessary but, on some Wine builds, not sufficient.
Under new-WoW64, Wine's `WMReader` can hand DQX the **compressed** WMV3 samples
instead of decoding them. DQX then passes that compressed data straight to Direct3D 9
as a video surface, and d3d9 has no idea what a WMV3 FourCC is:

```
Unrecognized 0x33564d57 (as fourcc: WMV3) WINED3DFORMAT
```

The visible symptom is a **blank/transparent movie window that never advances** — the
movie "freezes the instant the main segment starts." The logs show `WMVCore.DLL` and
`winegstreamer.dll` loading right before it.

The committed helper sets **`SteamGameId=638160`** in the launch environment by
default (`cmd_play`, configurable via `DQX_MOVIE_COMPAT_GAMEID`, empty to disable).
`638160` is a Steam app id that Wine's built-in **app-compat profile** maps to a
"force `WMReader` to deliver *decoded* samples" quirk, which would make `WMReader`
run `avdec_wmv3` internally (the pipeline above) so d3d9 receives normal frames.

> **Status: probably unnecessary — don't treat this key as load-bearing.** Two data
> points: (1) the wine-11.11/CachyOS capture decoded a full movie *with the key not
> set at all* — that build's `WMReader` already defaults to decoded output; and (2)
> later testing suggested the `638160` key wasn't actually needed even where it was
> first added, though that finding was never committed, so the default still ships
> it. Treat `638160` as a defensive default that is harmless where things already
> work, not as a confirmed requirement. If you're auditing or trimming the script,
> this is the first knob to re-test (set `DQX_MOVIE_COMPAT_GAMEID=` empty and see if
> anything regresses) rather than to trust.

## Two supported launch paths, and why Ubuntu needs Proton

| Path | Command | Movie strategy |
|------|---------|----------------|
| **Plain Wine** (CachyOS, default) | `./dqx.sh play` | system `gst-libav` (script also sets `SteamGameId=638160`, likely unnecessary — see below) |
| **GE-Proton11 via umu** (Ubuntu) | `./dqx.sh play-umu` | `GE-Proton11-1` + `PROTON_USE_WOW64=1` |

**We could not find any vanilla Wine 11 configuration that played movies (or even got
past `DQXTitle` startup) on Ubuntu**, so the Ubuntu path is forced onto
`GE-Proton11-1` through `umu`/`steamrt4`. There, the critical flag is
`PROTON_USE_WOW64=1` — it selects Proton's WoW64 path (in GE-Proton11 it sets
`WINEARCH=wow64`), which is required for the launcher → `DQXTitle` movie handoff.
Without it the launcher opens but the movie's OK button never spawns `DQXTitle.exe`.
GE-Proton11 under steamrt4 does not exhibit the early `DQXTitle.exe` access-violation
that WineHQ `wine-11.11` and UMU-Proton `10.0-4` hit on Ubuntu. (Note GE-Proton11's
own bundled GStreamer does the decoding on that path, so the `638160` app-id is not
needed there.)

This is also the reason the repo is still named `dqx-proton-helper`: it began on
Proton/umu, and Proton remains the working answer on at least one mainstream distro.

## Why the macOS / CrossOver port freezes at the main segment

Same class of bug as the Wine `WMReader` trap, one layer down. CrossOver's bundled
GStreamer typically ships **without `gst-libav`**, so there is no `avdec_wmv3` at all.
The intro/preamble may show, but the moment the stream switches to the actual WMV3
main segment there is no decoder to satisfy the `find_element_factories` lookup, the
transform never gets created, and either nothing decodes or DQX falls back to handing
compressed WMV3 to the graphics layer — exactly the freeze you observed.

The fix on that side is to get a genuine WMV3 decoder into CrossOver's GStreamer
(bundle/point it at `gst-libav`), **not** anything `.foz`/Proton-converter related.
On this Linux box the equivalent lookup succeeds because system `gst-libav` provides
`avdec_wmv3`, so the same negotiation resolves and the main segment plays.

## Reproducing the capture

```sh
mkdir -p /tmp/dqx-dot && rm -f /tmp/dqx-dot/*.dot
export GST_DEBUG_DUMP_DOT_DIR=/tmp/dqx-dot
export GST_DEBUG=2
export WINEDEBUG=+winegstreamer,+gstreamer,+quartz,+mfplat
./dqx.sh play 2>&1 | tee /tmp/dqx-movie.log
# play a movie fully, quit, then:
grep -c wg_transform_push_dmo /tmp/dqx-movie.log     # thousands ⇒ live decode happening
grep -i 'video/x-wmv\|avdec_wmv3' /tmp/dqx-movie.log # the WMV3 stream + decoder
grep -i 'protonvideoconv\|mediaconv\|foz'  /tmp/dqx-movie.log  # empty ⇒ no substitution
```

Bump `GST_DEBUG=4` if you want the explicit `Using "avdec_wmv3"` element-selection
lines (suppressed at level 2).
