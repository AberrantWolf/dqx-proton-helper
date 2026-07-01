/*
 * Render Japanese text through GDI and GDI+ to check Wine font behavior.
 *
 * Build:
 *   i686-w64-mingw32-gcc -Os -municode -o build/gdiplus-text-probe.exe tools/gdiplus-text-probe.c -lgdiplus -lgdi32
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <gdiplus.h>
#include <stdio.h>

static void print_wide(const WCHAR *s)
{
    char buf[512];
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, sizeof(buf), NULL, NULL);
    if (n > 0) fputs(buf, stdout);
    else fputs("<utf8-failed>", stdout);
}

static int count_non_white(const DWORD *pixels, int width, int height)
{
    int count = 0;
    for (int i = 0; i < width * height; ++i) {
        if ((pixels[i] & 0x00ffffff) != 0x00ffffff) ++count;
    }
    return count;
}

static HBITMAP make_bitmap(HDC hdc, int width, int height, DWORD **pixels_out)
{
    BITMAPINFO bi;
    ZeroMemory(&bi, sizeof(bi));
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = width;
    bi.bmiHeader.biHeight = -height;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    return CreateDIBSection(hdc, &bi, DIB_RGB_COLORS, (void **)pixels_out, NULL, 0);
}

static void fill_white(HDC hdc, int width, int height)
{
    HBRUSH brush = CreateSolidBrush(RGB(255, 255, 255));
    RECT r = {0, 0, width, height};
    FillRect(hdc, &r, brush);
    DeleteObject(brush);
}

static void probe_one(const WCHAR *face)
{
    const int width = 360, height = 80;
    const WCHAR *text = L"プレイヤー 1 【ユズタ】";
    HDC screen = GetDC(NULL);
    HDC hdc = CreateCompatibleDC(screen);
    DWORD *pixels = NULL;
    HBITMAP bitmap = make_bitmap(hdc, width, height, &pixels);
    HGDIOBJ old_bitmap = SelectObject(hdc, bitmap);
    LOGFONTW lf;
    HFONT hfont, old_font;
    int gdi_pixels, gdip_pixels;
    GdiplusStartupInput input;
    ULONG_PTR token = 0;
    GpGraphics *graphics = NULL;
    GpFont *font = NULL;
    GpSolidFill *brush = NULL;
    RectF rect;
    GpStatus s_start, s_graphics, s_font, s_brush, s_draw;

    ZeroMemory(&lf, sizeof(lf));
    lf.lfHeight = -13;
    lf.lfCharSet = SHIFTJIS_CHARSET;
    lstrcpynW(lf.lfFaceName, face, LF_FACESIZE);

    fill_white(hdc, width, height);
    hfont = CreateFontIndirectW(&lf);
    old_font = SelectObject(hdc, hfont);
    SetTextColor(hdc, RGB(0, 0, 0));
    SetBkMode(hdc, TRANSPARENT);
    TextOutW(hdc, 8, 8, text, lstrlenW(text));
    gdi_pixels = count_non_white(pixels, width, height);
    SelectObject(hdc, old_font);

    fill_white(hdc, width, height);
    ZeroMemory(&input, sizeof(input));
    input.GdiplusVersion = 1;
    s_start = GdiplusStartup(&token, &input, NULL);
    s_graphics = GdipCreateFromHDC(hdc, &graphics);
    s_font = GdipCreateFontFromLogfontW(hdc, &lf, &font);
    s_brush = GdipCreateSolidFill(0xff000000, &brush);
    rect.X = 8.0f;
    rect.Y = 8.0f;
    rect.Width = 340.0f;
    rect.Height = 50.0f;
    s_draw = GdipDrawString(graphics, text, -1, font, &rect, NULL, (GpBrush *)brush);
    gdip_pixels = count_non_white(pixels, width, height);

    printf("face=\"");
    print_wide(face);
    printf("\" gdiPixels=%d gdipPixels=%d status startup=%d graphics=%d font=%d brush=%d draw=%d\n",
           gdi_pixels, gdip_pixels, s_start, s_graphics, s_font, s_brush, s_draw);

    if (brush) GdipDeleteBrush((GpBrush *)brush);
    if (font) GdipDeleteFont(font);
    if (graphics) GdipDeleteGraphics(graphics);
    if (token) GdiplusShutdown(token);
    DeleteObject(hfont);
    SelectObject(hdc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(hdc);
    ReleaseDC(NULL, screen);
}

int wmain(void)
{
    probe_one(L"MS UI Gothic");
    probe_one(L"MS PGothic");
    probe_one(L"ＭＳ Ｐゴシック");
    probe_one(L"Meiryo UI");
    probe_one(L"IPAMonaPGothic");
    return 0;
}
