# DQXConfig UI scaling and button geometry

## Short version

High-DPI rendering is not the cause of the overlapping/oversized buttons. It
works correctly when the Japanese dialog font has the metrics that
`DQXConfig.exe` expects.

The reproducible failure is a font fallback:

- `DQXConfig.exe` lays out its dialogs for the 10-point font
  `ＭＳ ゴシック` (the Japanese/full-width spelling of MS Gothic).
- If that face is unavailable, Wine may substitute a host CJK font. In a clean
  Wine 11.11 prefix on the test machine it chose Noto Sans CJK JP.
- For the same requested `-13` pixel font height at 96 DPI, Wine reported a
  19-pixel text-metric height for Noto, versus 13 pixels for MS Gothic. Wine
  then made the dialog-unit-based child controls much taller while DQX kept
  the main page at its fixed size. The large buttons consequently overlapped.
- Installing IPAMona fixed the layout at both 96 and 192 DPI. A licensed MS
  Gothic install also worked.

CrossOver 26's High Resolution Mode is still worth enabling on a Retina Mac.
On plain Wine, setting 192 DPI is a useful 200% UI scale for a 4K display.
Keep the high-DPI setting and fix the font.

## Enable high DPI

### Plain Wine on Linux

Close DQX and every other program using the prefix. Open Wine Configuration:

```sh
WINEPREFIX="${DQX_PREFIX:-$HOME/Games/dqx-prefix}" "${WINE:-wine}" winecfg
```

On the **Graphics** tab, set **Screen resolution** to **192 DPI** for 200%
scaling. Useful values are 120 DPI (125%), 144 DPI (150%), 168 DPI (175%), and
192 DPI (200%). Close and restart all Wine processes in the prefix after
changing it.

The equivalent registry command is:

```sh
WINEPREFIX="${DQX_PREFIX:-$HOME/Games/dqx-prefix}" "${WINE:-wine}" \
  reg add 'HKCU\Control Panel\Desktop' \
  /v LogPixels /t REG_DWORD /d 192 /f
```

To return to the normal scale, set it back to 96. This is a prefix-wide
setting, so it also enlarges the installer, launcher, and other Wine dialogs.
Desktop scaling may apply another scale on top of Wine's, especially under
XWayland, so verify the result on the desktop session you actually use.

### CrossOver on macOS

Select the DQX bottle, open **Advanced Settings**, and enable **High Resolution
Mode**. CrossOver documents this as disabling pixel doubling and reporting 192
DPI to the application. In effect, the app draws at twice the pixel resolution
and macOS presents it at Retina density.

Do not manually enable only `RetinaMode`. The intended configuration pairs:

- `HKCU\Software\Wine\Mac Driver\RetinaMode` = `Y`
- `HKCU\Control Panel\Desktop\LogPixels` = 192 (`0xC0`)

If only one half is active, the whole UI can be half-size or double-size.
CrossOver's switch should manage the pair. Its current documentation is
[Advanced Settings in CrossOver Mac 26](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac-26).

## Fix the Japanese dialog font

### Plain Wine

The helper's preferred setup already does this:

```sh
WINEPREFIX="${DQX_PREFIX:-$HOME/Games/dqx-prefix}" \
  winetricks -q fakejapanese_ipamona
```

Restart every process in the prefix afterward. Merely having a Japanese font
is not enough: the substitute needs MS Gothic-like vertical and horizontal
metrics, and Wine must resolve the exact localized family name
`ＭＳ ゴシック`. `fakejapanese_ipamona` installs aliases for both the ASCII and
localized names.

### CrossOver Mac without Winetricks

If a current CrossOver build does not expose the old built-in Winetricks UI,
that is not a blocker. Winetricks is not required for this fix.

First try installing CodeWeavers' own
[Japanese Font Override](https://www.codeweavers.com/compatibility/crossover/japanese-font-override)
component into the existing DQX bottle: use **Install Application**, search for
**Japanese Font Override**, and select the DQX bottle as the destination. This
is a CrossTie component, not Winetricks.

If that component is unavailable or its Ume Gothic metrics do not match this
DQXConfig build, install IPAMona manually:

1. Obtain the five IPAMona font files. The current Winetricks recipe uses the
   archived `opfc-ModuleHP-1.1.1_withIPAMonaFonts-1.0.8.tar.gz` package with
   SHA-256 `ab77beea3b051abf606cd8cd3badf6cb24141ef145c60f508fcfef1e3852bb9d`.
   The filenames used by the validated setup are `ipag-mona.ttf`,
   `ipagp-mona.ttf`, `ipagui-mona.ttf`, `ipam-mona.ttf`, and
   `ipamp-mona.ttf`.
2. In CrossOver, open the DQX bottle's C: drive and copy them into
   `windows/Fonts`.
3. Run `regedit` in that bottle through **Run Command**. Under
   `HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts`,
   create these string values:

   | Value name | Data |
   | --- | --- |
   | `IPAMonaGothic (TrueType)` | `ipag-mona.ttf` |
   | `IPAMonaPGothic (TrueType)` | `ipagp-mona.ttf` |
   | `IPAMonaUIGothic (TrueType)` | `ipagui-mona.ttf` |
   | `IPAMonaMincho (TrueType)` | `ipam-mona.ttf` |
   | `IPAMonaPMincho (TrueType)` | `ipamp-mona.ttf` |

4. Under `HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements`, create these
   string values. The full-width Japanese spellings are important:

   | Value name | Data |
   | --- | --- |
   | `MS Gothic` | `IPAMonaGothic` |
   | `MS PGothic` | `IPAMonaPGothic` |
   | `MS UI Gothic` | `IPAMonaUIGothic` |
   | `MS Mincho` | `IPAMonaMincho` |
   | `MS PMincho` | `IPAMonaPMincho` |
   | `ＭＳ ゴシック` | `IPAMonaGothic` |
   | `ＭＳ Ｐゴシック` | `IPAMonaPGothic` |
   | `ＭＳ 明朝` | `IPAMonaMincho` |
   | `ＭＳ Ｐ明朝` | `IPAMonaPMincho` |

5. Quit every process in the bottle, quit CrossOver, and reopen it. Wine builds
   its font list early in process startup; a still-running bottle helper can
   make a font change appear ineffective.

A real MS Gothic file copied from a properly licensed Windows/Office
installation also works, but it must not be redistributed with this project.

## Why this application is unusually sensitive

The `DQXConfig.exe` examined on 2026-06-30 has SHA-256
`8a12e6c906143d1f096c1dc76373613c6f63ff05893e09ef67adc786b9101df0`.
Its relevant properties are:

- 32-bit Win32/MFC GUI, with MFC linked into the executable.
- Embedded manifest: legacy per-monitor DPI awareness, `True/PM`.
- Main DIALOGEX resources: 10-point `ＭＳ ゴシック`, authored in dialog units.
- The resource includes charset 128 (Shift-JIS), but the Wine/CrossOver dialog
  implementation examined discards that charset byte and calls `CreateFontW`
  with `DEFAULT_CHARSET`. That makes the fallback more dependent on the
  installed fonts, host font enumeration, and aliases.

CrossOver 26.2's Wine source handles `True/PM` as per-monitor-aware. Its dialog
manager computes the font pixel height from `LogPixels`, measures the resolved
font, and converts each dialog-unit rectangle using those measurements:

```text
font pixels = point size * DPI / 72
control x/width = dialog units * measured average character width / 4
control y/height = dialog units * measured character height / 8
```

Because the process is DPI-aware, Wine does not rescue it with bitmap DPI
virtualization. Because DQX combines a fixed main-page composition with
font-derived child geometry, a bad font can make the buttons wrong even when
the outer window and banner still look normal.

## Reproduction results

These tests used the same current `DQXConfig.exe` and Wine 11.11 Staging under
X11. The 192-DPI tests model the Windows-side scaling used by CrossOver High
Resolution Mode; CrossOver's macOS driver adds the Retina coordinate mapping.

| Prefix configuration | DPI | Resolved dialog font | Result |
| --- | ---: | --- | --- |
| Licensed MS Gothic present | 96 | `ＭＳ ゴシック`, metric height 13 | Correct 656x468 layout |
| Clean prefix, no MS Gothic alias | 96 | Noto Sans CJK JP, metric height 19 | Oversized, overlapping buttons in the same 656x468 page |
| Clean prefix, no MS Gothic alias | 192 | Noto Sans CJK JP | Same bad proportions at roughly 2x pixels (1318x943) |
| IPAMona installed and aliased | 192 | IPAMona Gothic | Correct high-DPI 1318x943 layout |

The last row is the desired 4K/Retina setup: more pixels and larger Wine UI
scaling without corrupting the control layout.

## Other configurations that can change the result

In descending order of likelihood:

1. **Incomplete font aliases.** An alias for `MS Gothic` does not necessarily
   cover `ＭＳ ゴシック`. The exact localized name is what these dialog
   resources request.
2. **Different host fallback fonts or font order.** Noto, Hiragino, Ume, VL
   Gothic, and other CJK faces have different metrics. Locale and Wine build
   options can change which one wins.
3. **Stale font discovery.** Installing a font without fully restarting the
   bottle can leave the previous fallback active.
4. **Mismatched macOS Retina and Windows DPI settings.** `RetinaMode=Y` with
   96 DPI makes the app globally too small; 192 DPI without Retina coordinate
   scaling makes it globally too large on macOS.
5. **A DPI-awareness override.** CrossOver Wine checks an Image File Execution
   Options `dpiAwareness` value before the executable manifest. Old bottle
   tweaks or compatibility profiles can therefore change whether Wine scales
   this app.
6. **Display-mode or mixed-monitor transitions on macOS.** The Mac driver uses
   a prefix-wide Retina coordinate mode and can disable it when the main
   display leaves its original mode. Moving between Retina and non-Retina
   displays is not equivalent to Windows per-monitor DPI v2.
7. **Native DLL/theme overrides.** Replacing `comctl32`, `uxtheme`, or related
   UI DLLs can change control rendering. This is less consistent with the
   reproduced geometry failure than the font substitution is.

## Quick diagnosis

Check the configured DPI:

```sh
WINEPREFIX="${DQX_PREFIX:-$HOME/Games/dqx-prefix}" "${WINE:-wine}" \
  reg query 'HKCU\Control Panel\Desktop' /v LogPixels
```

With Wine font tracing enabled, the failing test contained:

```text
font_SelectFont L"\ff2d\ff33 \30b4\30b7\30c3\30af", h=-13
select_font Chosen: L"Noto Sans CJK JP"
Height = 19
```

The working test contained:

```text
font_SelectFont L"\ff2d\ff33 \30b4\30b7\30c3\30af", h=-13
select_font Chosen: L"\ff2d\ff33 \30b4\30b7\30c3\30af"
Height = 13
```

The escaped family in those traces is `ＭＳ ゴシック`. Seeing Noto,
Hiragino, or another host fallback there is the strongest indicator that the
button issue is a font-metrics mismatch.

## References

- [CrossOver Mac 26 Advanced Settings](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac-26)
- [CodeWeavers' published CrossOver source](https://www.codeweavers.com/crossover/source)
- [Microsoft DIALOGEX resource format](https://learn.microsoft.com/en-us/windows/win32/menurc/dialogex-resource)
- [Microsoft MFC dialog-unit and MapDialogRect behavior](https://learn.microsoft.com/en-us/cpp/mfc/reference/cdialog-class)
- [Microsoft DPI-awareness manifest values](https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process)
