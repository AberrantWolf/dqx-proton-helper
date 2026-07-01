/*
 * Minimal GDI font resolver/metrics probe for DQX Wine/CrossOver debugging.
 *
 * Build:
 *   i686-w64-mingw32-gcc -Os -municode -o font-probe.exe tools/font-probe.c -lgdi32
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>

static void print_wide(const WCHAR *s)
{
    char buf[512];
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, sizeof(buf), NULL, NULL);
    if (n > 0) {
        fputs(buf, stdout);
        return;
    }
    fputs("<utf8-conversion-failed>", stdout);
}

static void probe_name(HDC hdc, const WCHAR *name, int height)
{
    LOGFONTW lf;
    HFONT font, old;
    TEXTMETRICW tm;
    WCHAR face[LF_FACESIZE];

    ZeroMemory(&lf, sizeof(lf));
    lf.lfHeight = height;
    lf.lfCharSet = DEFAULT_CHARSET;
    lf.lfQuality = DEFAULT_QUALITY;
    lstrcpynW(lf.lfFaceName, name, LF_FACESIZE);

    font = CreateFontIndirectW(&lf);
    if (!font) {
        wprintf(L"request=");
        print_wide(name);
        printf(" h=%d -> CreateFontIndirectW failed\n", height);
        return;
    }

    old = SelectObject(hdc, font);
    ZeroMemory(&tm, sizeof(tm));
    ZeroMemory(face, sizeof(face));
    GetTextMetricsW(hdc, &tm);
    GetTextFaceW(hdc, LF_FACESIZE, face);

    printf("request=");
    print_wide(name);
    printf(" h=%d -> face=", height);
    print_wide(face);
    printf(" tmHeight=%ld ascent=%ld descent=%ld aveWidth=%ld maxWidth=%ld charset=%u pitchFamily=0x%02x\n",
           tm.tmHeight, tm.tmAscent, tm.tmDescent, tm.tmAveCharWidth,
           tm.tmMaxCharWidth, tm.tmCharSet, tm.tmPitchAndFamily);

    SelectObject(hdc, old);
    DeleteObject(font);
}

int wmain(void)
{
    static const WCHAR *names[] = {
        L"MS UI Gothic",
        L"MS Gothic",
        L"MS PGothic",
        L"MS Shell Dlg",
        L"MS Shell Dlg 2",
        L"ＭＳ ゴシック",
        L"ＭＳ Ｐゴシック",
        L"IPAMonaUIGothic",
        L"IPAMonaGothic",
        L"IPAMonaPGothic",
        L"Ume UI Gothic",
        L"Tahoma",
        L"Meiryo",
        L"Meiryo UI",
        NULL
    };
    HDC hdc = GetDC(NULL);
    int i;

    if (!hdc) return 1;
    printf("LogPixelsY=%d\n", GetDeviceCaps(hdc, LOGPIXELSY));
    for (i = 0; names[i]; ++i)
        probe_name(hdc, names[i], -13);
    ReleaseDC(NULL, hdc);
    return 0;
}
