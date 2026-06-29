# DQX movie playback: verified paths and diagnostics

Movie playback is one of the most fragile parts of running DQX outside Windows.
This document separates behavior captured on working systems from hypotheses that
still need evidence on other platforms.

The tested client stores its game data in packed `.dat*` files; no loose `.wmv`
or `.asf` assets were found in the install. Runtime tracing nevertheless identifies
the captured video stream as WMV3 (Windows Media Video 9) carried through the
ASF/Windows Media stack.

## TL;DR

- On the verified plain-Wine path, DQX's movie stream is decoded live by
  Wine's GStreamer bridge using the host `asfdemux`, `avdec_wmv3`, and
  conversion elements.
- The detailed CachyOS capture found no
  `protonvideoconverter`, `mediaconv`, Theora, or
  `transcoded_video.foz` substitution.
- GE-Proton11-1 is a different path: its release deliberately removed the
  GStreamer libraries and routes Quartz through Wine DMO and FFmpeg.
- A missing decoder should fail when WMV3 decoding is first required. A movie
  that decodes normally and then pauses part-way needs timestamp and audio/video
  evidence before it is blamed on `gst-libav`.

Proton's pre-transcoded-video mechanism exists, but it is not used by the
default helper path. DQX is not launched as a Steam title here, and
`protonvideoconverter` was not registered in the captured environment. A
`transcoded_video.foz` belonging to another Steam game is unrelated.

## Verified plain-Wine decode path

A successful CachyOS Wine 11.11/new-WoW64 run was captured with
`GST_DEBUG` and
`WINEDEBUG=+winegstreamer,+gstreamer,+quartz,+mfplat`. The conceptual flow
was:

```text
packed DQX data
      |
      v
DQX Windows media APIs (WMReader / quartz / mfplat)
      |
      v
winegstreamer -> wg_transform
      |            asfdemux -> avdec_wmv3 (gst-libav) -> videoconvert
      v
decoded samples -> Direct3D 9 (wined3d) and Wine audio -> screen/speakers
```

One complete successful capture showed:

- An `avdec_wmv3` instance actively decoding
  `video/x-wmv, wmvversion=3, format=WMV3`; caps were negotiated first at
  1920x1080 and then at 1280x720.
- Approximately 6,000 `wg_transform_push_dmo` calls and 27,600 decoded reads,
  with timestamps spanning minutes. The counts are specific to that run; their
  significance is that decode continued rather than stopping at startup.
- No matches for `protonvideoconverter`, `mediaconv`, Theora, or
  `transcoded_video.foz`.
- A few `Subclass refused caps`, `find_element_factories: Failed`, and
  `wg_transform_create: Failed` messages during the first roughly 0.24 seconds.
  In this successful run Wine tried several media types, rejected incompatible
  combinations, selected `avdec_wmv3`, and continued. Those early recovered
  messages are not, by themselves, a failure signature.

`GST_DEBUG_DUMP_DOT_DIR` produced no graph for this path. Winegstreamer creates
per-transform bins rather than a convenient named top-level pipeline, so the
`wg_transform`, caps, decoder-selection, and timestamp traces are the useful
evidence.

### Host requirements

For this plain-Wine path, `./dqx.sh doctor` checks for:

- `asfdemux` for ASF/WMV demuxing, supplied by `gst-plugins-ugly`
  (`gstreamer1.0-plugins-ugly` on Ubuntu);
- `avdec_wmv3` for video and `avdec_wmav2` for audio, supplied by
  `gst-libav` (`gstreamer1.0-libav` on Ubuntu); and
- `videoconvert`, `audioconvert`, and `audioresample`, supplied by
  `gst-plugins-base`.

A controlled Ubuntu test hid `libgstlibav.so` while leaving the ASF demuxer and
base conversion plugins visible. The helper then reported exactly
`avdec_wmv3 avdec_wmav2` as missing. That is a useful first check for another
Linux host, but it only describes the plugin environment seen by the selected
Wine runtime.

With active new WoW64, the 32-bit Windows client is hosted by Wine's 64-bit Unix
side. The successful Ubuntu process maps contained the 64-bit host GStreamer,
libav, OpenGL, and NVIDIA libraries; a separate i386 GStreamer stack was not
part of this path. Windows codec packs, LAV Filters, `wmp`, and WebView2 were
not involved in the captured plain-Wine decode flow.

## A separate WMReader compressed-sample signature

A local `wine-cachyos 10.0-20260425` build exposed a different failure. Its
WMReader path could return compressed WMV3 samples where DQX expected decoded
video. DQX then handed the WMV3 FourCC to Direct3D 9:

```text
Unrecognized 0x33564d57 (as fourcc: WMV3) WINED3DFORMAT
```

The visible result was a blank or transparent movie window that did not advance.
That exact combination—media DLLs loaded, compressed WMV3 reaching D3D9, and
the FourCC error—is the reason the opt-in workaround exists:

```sh
DQX_MOVIE_COMPAT_GAMEID=638160 ./dqx.sh play
```

On that affected downstream build, `SteamGameId=638160` selected compatibility
behavior that made WMReader return decoded samples. It is a borrowed compatibility
ID, not DQX's identity and not a general requirement. The helper now leaves it
disabled by default. Wine 11.11 on CachyOS and WineHQ Staging 11.11 on Ubuntu both
played movies without it, so use it only for the matching compressed-WMV3/D3D9
signature.

## Verified runtime matrix

| Host and runtime | Required mode | Observed movie result | Decode path |
|---|---|---|---|
| CachyOS, Wine 11.11 | Pure-new-WoW64 build; helper selects `WINEARCH=win64` | Detailed live-decode capture; title/gameplay and memory-projector coverage | Host GStreamer/`gst-libav` |
| Ubuntu 24.04, WineHQ Staging 11.11 | Dual/multilib build; `WINEARCH=wow64` forces new WoW64 | Complete title movie with audio, then login, menus, and movement; memory projector not retested | Host GStreamer/`gst-libav` |
| Ubuntu, local wine-cachyos 10.0-20260425 | Build-specific new-WoW64 path | Title movie worked with the 638160 workaround after the compressed-sample failure | Host GStreamer plus downstream WMReader compatibility behavior |
| Ubuntu, GE-Proton11-1 through umu | `PROTON_USE_WOW64=1` | Title flow worked in the earlier fallback test | Wine DMO/FFmpeg, according to the GE-Proton11-1 design |

The Ubuntu WineHQ failure that originally motivated the Proton fallback was an
architecture-selection problem. `WINEARCH=win64` selected old WoW64 in WineHQ's
dual/multilib installation; `WINEARCH=wow64` selected the tested new path and
removed the pre-media `DQXTitle.exe` crash. Plain Wine is therefore the default
on both tested Linux hosts.

GE-Proton11-1/umu remains useful as a fallback, but it should not be described as
bundling the GStreamer path above. The official
[GE-Proton11-1 release notes](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-1)
say its GStreamer libraries were removed and its Quartz route changed to Wine
DMO and FFmpeg. GStreamer plugin diagnostics do not test that fallback backend.

## macOS/CrossOver: hypothesis, not diagnosis

The reported macOS/CrossOver symptom is a movie that pauses part-way through,
with audio/timing suspected. That is materially different from both verified
Linux failure signatures: a pre-media executable crash and a blank window that
immediately sends compressed WMV3 to D3D9.

The earlier claim that CrossOver on macOS “typically ships without gst-libav” is
not established. CodeWeavers documents fixes for
[missing GStreamer libav](https://support.codeweavers.com/missinggstreamer1libav)
and a
[missing ASF demuxer](https://support.codeweavers.com/missing-libraries/missinggstreamer1asfdemux),
but those pages are specifically CrossOver Linux guidance. They do not prove
which backend or plugins a particular macOS CrossOver build uses. Installing or
copying plugins should wait until the bottle's actual media backend, search path,
binary architecture, and decoder selection are known.

Use the first matching signature:

1. If `DQXTitle.exe` faults before `quartz`, `winegstreamer`, or D3D9 loads,
   investigate Wine mode/startup state, not codecs.
2. If `avdec_wmv3` never instantiates and element-factory failures continue from
   the first WMV3 frame, a missing or undiscoverable decoder is plausible.
3. If compressed `WMV3` reaches D3D9 and produces the FourCC error above, test
   the narrowly scoped WMReader workaround.
4. If a decoder is active and video/audio timestamps advance for a while before
   stopping, compare the last successful timestamps for each stream. An audio
   sink/clock, backpressure, or a mid-stream format transition is then a stronger
   lead than a decoder that was absent from startup.
5. If the runtime uses a DMO/FFmpeg path like GE-Proton11-1, GStreamer fixes are
   irrelevant to that run.

The title movie is enough for this first comparison; there is no need to jump
straight to the memory projector. Record the exact CrossOver version, macOS and
CPU architecture, bottle architecture, and graphics backend alongside the log.

## Reproducing the Linux capture

This recipe is for the plain-Wine/GStreamer path and can produce a large log:

```sh
GST_DEBUG=2 \
WINEDEBUG=+winegstreamer,+gstreamer,+quartz,+mfplat \
  ./dqx.sh play 2>&1 | tee /tmp/dqx-movie.log

# Play the target movie through, quit, then inspect the same timeline.
rg -c 'wg_transform_push_dmo' /tmp/dqx-movie.log
rg -i 'video/x-wmv|avdec_wmv3|avdec_wmav2' /tmp/dqx-movie.log
rg -i 'protonvideoconv|mediaconv|transcoded_video\.foz|theora' /tmp/dqx-movie.log
rg -i 'timestamp|pts|duration|audio|wma' /tmp/dqx-movie.log
```

Use `GST_DEBUG=4` when the explicit `Using "avdec_wmv3"` selection is needed.
A zero result from the Proton-converter search is expected on the verified plain
Wine path. A few rejected caps at startup matter only if negotiation never
recovers.

For a useful comparison report, include:

- host OS, CPU/GPU, and exact Wine/Proton/CrossOver build;
- prefix or bottle architecture and the active old/new-WoW64 mode;
- graphics and media backend actually loaded;
- which movie was tested and the wall-clock/media timestamp of any pause;
- whether video, audio, or both stopped first;
- the first permanent decoder/transform error, rather than recovered negotiation
  attempts; and
- whether either the WMV3 D3D9 FourCC error or Proton-converter evidence appeared.
