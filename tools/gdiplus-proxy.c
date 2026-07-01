/*
 * GDI+ proxy for DQXLauncher.
 *
 * Put this DLL next to DQXLauncher.exe as gdiplus.dll and put Wine's gdiplus.dll
 * next to it as gdiplus_real.dll. It works around Wine GDI+ differences that
 * keep the owner-drawn player list text from rendering on macOS CrossOver.
 *
 * Set DQX_GDIPLUS_PROXY_LOG=1 to log calls to C:\users\Public.
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
#include <stdarg.h>

static HMODULE real_gdiplus;
extern IMAGE_DOS_HEADER __ImageBase;

static void log_line(const char *fmt, ...)
{
    FILE *f;
    va_list ap;
    char enabled[8];

    if (!GetEnvironmentVariableA("DQX_GDIPLUS_PROXY_LOG", enabled, sizeof(enabled))) return;
    f = fopen("C:\\users\\Public\\dqx-gdiplus-proxy.log", "ab");
    if (!f) return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static FARPROC real_proc(const char *name)
{
    WCHAR path[MAX_PATH];

    if (!real_gdiplus) {
        GetModuleFileNameW((HMODULE)&__ImageBase, path, MAX_PATH);
        WCHAR *slash = wcsrchr(path, L'\\');
        if (slash) lstrcpyW(slash + 1, L"gdiplus_real.dll");
        real_gdiplus = LoadLibraryW(path);
        log_line("proxy load real_gdiplus=%p gle=%lu", real_gdiplus, GetLastError());
    }
    if (!real_gdiplus) return NULL;
    return GetProcAddress(real_gdiplus, name);
}

#define RESOLVE(name) (p_##name)real_proc(#name)

typedef GpStatus (WINAPI *p_GdiplusStartup)(ULONG_PTR *, const GdiplusStartupInput *, GdiplusStartupOutput *);
typedef VOID (WINAPI *p_GdiplusShutdown)(ULONG_PTR);
typedef GpStatus (WINAPI *p_GdipCreateFromHDC)(HDC, GpGraphics **);
typedef GpStatus (WINAPI *p_GdipDrawImagePointRectI)(GpGraphics *, GpImage *, INT, INT, INT, INT, INT, INT, GpUnit);
typedef GpStatus (WINAPI *p_GdipSetInterpolationMode)(GpGraphics *, InterpolationMode);
typedef GpStatus (WINAPI *p_GdipDrawImageRect)(GpGraphics *, GpImage *, REAL, REAL, REAL, REAL);
typedef GpStatus (WINAPI *p_GdipDrawImageRectRect)(GpGraphics *, GpImage *, REAL, REAL, REAL, REAL, REAL, REAL, REAL, REAL, GpUnit, const GpImageAttributes *, DrawImageAbort, VOID *);
typedef GpStatus (WINAPI *p_GdipDrawImageRectI)(GpGraphics *, GpImage *, INT, INT, INT, INT);
typedef GpStatus (WINAPI *p_GdipCloneBrush)(GpBrush *, GpBrush **);
typedef GpStatus (WINAPI *p_GdipDrawString)(GpGraphics *, GDIPCONST WCHAR *, INT, GDIPCONST GpFont *, GDIPCONST RectF *, GDIPCONST GpStringFormat *, GDIPCONST GpBrush *);
typedef GpStatus (WINAPI *p_GdipCreateFontFromLogfontW)(HDC, GDIPCONST LOGFONTW *, GpFont **);
typedef GpStatus (WINAPI *p_GdipCreateSolidFill)(ARGB, GpSolidFill **);
typedef GpStatus (WINAPI *p_GdipDeleteBrush)(GpBrush *);
typedef GpStatus (WINAPI *p_GdipGraphicsClear)(GpGraphics *, ARGB);
typedef GpStatus (WINAPI *p_GdipCreateBitmapFromHBITMAP)(HBITMAP, HPALETTE, GpBitmap **);
typedef GpStatus (WINAPI *p_GdipGetImageHeight)(GpImage *, UINT *);
typedef GpStatus (WINAPI *p_GdipGetImagePaletteSize)(GpImage *, INT *);
typedef GpStatus (WINAPI *p_GdipDeleteFont)(GpFont *);
typedef GpStatus (WINAPI *p_GdipBitmapUnlockBits)(GpBitmap *, BitmapData *);
typedef GpStatus (WINAPI *p_GdipCloneImage)(GpImage *, GpImage **);
typedef GpStatus (WINAPI *p_GdipDrawImageI)(GpGraphics *, GpImage *, INT, INT);
typedef GpStatus (WINAPI *p_GdipCreateBitmapFromScan0)(INT, INT, INT, PixelFormat, BYTE *, GpBitmap **);
typedef GpStatus (WINAPI *p_GdipGetImageWidth)(GpImage *, UINT *);
typedef GpStatus (WINAPI *p_GdipGetImagePalette)(GpImage *, ColorPalette *, INT);
typedef GpStatus (WINAPI *p_GdipDeleteGraphics)(GpGraphics *);
typedef GpStatus (WINAPI *p_GdipGetImageGraphicsContext)(GpImage *, GpGraphics **);
typedef GpStatus (WINAPI *p_GdipCreateBitmapFromStream)(IStream *, GpBitmap **);
typedef VOID (WINAPI *p_GdipFree)(VOID *);
typedef GpStatus (WINAPI *p_GdipGetImagePixelFormat)(GpImage *, PixelFormat *);
typedef GpStatus (WINAPI *p_GdipDisposeImage)(GpImage *);
typedef VOID *(WINAPI *p_GdipAlloc)(size_t);
typedef GpStatus (WINAPI *p_GdipBitmapLockBits)(GpBitmap *, GDIPCONST Rect *, UINT, PixelFormat, BitmapData *);

GpStatus WINAPI GdiplusStartup(ULONG_PTR *token, const GdiplusStartupInput *input, GdiplusStartupOutput *output)
{
    p_GdiplusStartup fn = RESOLVE(GdiplusStartup);
    GpStatus s = fn ? fn(token, input, output) : GenericError;
    log_line("GdiplusStartup -> %d", s);
    return s;
}

VOID WINAPI GdiplusShutdown(ULONG_PTR token) { p_GdiplusShutdown fn = RESOLVE(GdiplusShutdown); if (fn) fn(token); }
GpStatus WINAPI GdipCreateFromHDC(HDC hdc, GpGraphics **graphics) { p_GdipCreateFromHDC fn = RESOLVE(GdipCreateFromHDC); return fn ? fn(hdc, graphics) : GenericError; }
GpStatus WINAPI GdipDrawImagePointRectI(GpGraphics *g, GpImage *i, INT x, INT y, INT sx, INT sy, INT sw, INT sh, GpUnit u) { p_GdipDrawImagePointRectI fn = RESOLVE(GdipDrawImagePointRectI); return fn ? fn(g, i, x, y, sx, sy, sw, sh, u) : GenericError; }
GpStatus WINAPI GdipSetInterpolationMode(GpGraphics *g, InterpolationMode m) { p_GdipSetInterpolationMode fn = RESOLVE(GdipSetInterpolationMode); return fn ? fn(g, m) : GenericError; }
GpStatus WINAPI GdipDrawImageRect(GpGraphics *g, GpImage *i, REAL x, REAL y, REAL w, REAL h) { p_GdipDrawImageRect fn = RESOLVE(GdipDrawImageRect); return fn ? fn(g, i, x, y, w, h) : GenericError; }
GpStatus WINAPI GdipDrawImageRectRect(GpGraphics *g, GpImage *i, REAL dx, REAL dy, REAL dw, REAL dh, REAL sx, REAL sy, REAL sw, REAL sh, GpUnit u, const GpImageAttributes *a, DrawImageAbort cb, VOID *d) { p_GdipDrawImageRectRect fn = RESOLVE(GdipDrawImageRectRect); return fn ? fn(g, i, dx, dy, dw, dh, sx, sy, sw, sh, u, a, cb, d) : GenericError; }
GpStatus WINAPI GdipDrawImageRectI(GpGraphics *g, GpImage *i, INT x, INT y, INT w, INT h) { p_GdipDrawImageRectI fn = RESOLVE(GdipDrawImageRectI); return fn ? fn(g, i, x, y, w, h) : GenericError; }
GpStatus WINAPI GdipCloneBrush(GpBrush *b, GpBrush **clone) { p_GdipCloneBrush fn = RESOLVE(GdipCloneBrush); return fn ? fn(b, clone) : GenericError; }
GpStatus WINAPI GdipDrawString(GpGraphics *g, GDIPCONST WCHAR *s, INT len, GDIPCONST GpFont *f, GDIPCONST RectF *r, GDIPCONST GpStringFormat *fmt, GDIPCONST GpBrush *b)
{
    p_GdipDrawString fn = RESOLVE(GdipDrawString);
    RectF fixed_rect;
    GDIPCONST RectF *use_rect = r;
    GpStatus st;

    if (r && (r->Width <= 0.0f || r->Height <= 0.0f)) {
        fixed_rect = *r;
        if (fixed_rect.Width <= 0.0f) fixed_rect.Width = 280.0f;
        if (fixed_rect.Height <= 0.0f) fixed_rect.Height = 32.0f;
        use_rect = &fixed_rect;
    }
    st = fn ? fn(g, s, len, f, use_rect, fmt, b) : GenericError;
    log_line("GdipDrawString len=%d rect=%g,%g,%g,%g use=%g,%g,%g,%g -> %d",
             len,
             r ? r->X : -1.0, r ? r->Y : -1.0, r ? r->Width : -1.0, r ? r->Height : -1.0,
             use_rect ? use_rect->X : -1.0, use_rect ? use_rect->Y : -1.0,
             use_rect ? use_rect->Width : -1.0, use_rect ? use_rect->Height : -1.0,
             st);
    return st;
}

static void substitute_face(LOGFONTW *copy)
{
    if (!lstrcmpiW(copy->lfFaceName, L"MS UI Gothic") ||
        !lstrcmpiW(copy->lfFaceName, L"Meiryo UI") ||
        !lstrcmpiW(copy->lfFaceName, L"Meiryo")) {
        lstrcpynW(copy->lfFaceName, L"IPAMonaUIGothic", LF_FACESIZE);
    } else if (!lstrcmpiW(copy->lfFaceName, L"MS PGothic") ||
               !lstrcmpiW(copy->lfFaceName, L"ＭＳ Ｐゴシック")) {
        lstrcpynW(copy->lfFaceName, L"IPAMonaPGothic", LF_FACESIZE);
    } else if (!lstrcmpiW(copy->lfFaceName, L"MS Gothic") ||
               !lstrcmpiW(copy->lfFaceName, L"ＭＳ ゴシック")) {
        lstrcpynW(copy->lfFaceName, L"IPAMonaGothic", LF_FACESIZE);
    }
}

GpStatus WINAPI GdipCreateFontFromLogfontW(HDC hdc, GDIPCONST LOGFONTW *lf, GpFont **font)
{
    p_GdipCreateFontFromLogfontW fn = RESOLVE(GdipCreateFontFromLogfontW);
    GpStatus st;
    LOGFONTW copy;

    if (!fn) return GenericError;
    st = fn(hdc, lf, font);
    log_line("GdipCreateFontFromLogfontW face=%ls height=%ld charset=%u -> %d",
             lf ? lf->lfFaceName : L"(null)", lf ? lf->lfHeight : 0, lf ? lf->lfCharSet : 0, st);
    if (st == Ok || !lf || !font) return st;

    copy = *lf;
    substitute_face(&copy);
    if (copy.lfCharSet == DEFAULT_CHARSET || copy.lfCharSet == ANSI_CHARSET) copy.lfCharSet = SHIFTJIS_CHARSET;
    st = fn(hdc, &copy, font);
    log_line("GdipCreateFontFromLogfontW retry face=%ls height=%ld charset=%u -> %d",
             copy.lfFaceName, copy.lfHeight, copy.lfCharSet, st);
    if (st == Ok) return st;

    if (copy.lfHeight > 0) copy.lfHeight = -copy.lfHeight;
    st = fn(hdc, &copy, font);
    log_line("GdipCreateFontFromLogfontW retry2 face=%ls height=%ld charset=%u -> %d",
             copy.lfFaceName, copy.lfHeight, copy.lfCharSet, st);
    return st;
}
GpStatus WINAPI GdipCreateSolidFill(ARGB color, GpSolidFill **brush) { p_GdipCreateSolidFill fn = RESOLVE(GdipCreateSolidFill); ARGB fixed = color; if ((fixed & 0xff000000) == 0) fixed |= 0xff000000; log_line("GdipCreateSolidFill color=0x%08lx fixed=0x%08lx", (unsigned long)color, (unsigned long)fixed); return fn ? fn(fixed, brush) : GenericError; }
GpStatus WINAPI GdipDeleteBrush(GpBrush *b) { p_GdipDeleteBrush fn = RESOLVE(GdipDeleteBrush); return fn ? fn(b) : GenericError; }
GpStatus WINAPI GdipGraphicsClear(GpGraphics *g, ARGB c) { p_GdipGraphicsClear fn = RESOLVE(GdipGraphicsClear); return fn ? fn(g, c) : GenericError; }
GpStatus WINAPI GdipCreateBitmapFromHBITMAP(HBITMAP h, HPALETTE p, GpBitmap **b) { p_GdipCreateBitmapFromHBITMAP fn = RESOLVE(GdipCreateBitmapFromHBITMAP); return fn ? fn(h, p, b) : GenericError; }
GpStatus WINAPI GdipGetImageHeight(GpImage *i, UINT *h) { p_GdipGetImageHeight fn = RESOLVE(GdipGetImageHeight); return fn ? fn(i, h) : GenericError; }
GpStatus WINAPI GdipGetImagePaletteSize(GpImage *i, INT *s) { p_GdipGetImagePaletteSize fn = RESOLVE(GdipGetImagePaletteSize); return fn ? fn(i, s) : GenericError; }
GpStatus WINAPI GdipDeleteFont(GpFont *f) { p_GdipDeleteFont fn = RESOLVE(GdipDeleteFont); return fn ? fn(f) : GenericError; }
GpStatus WINAPI GdipBitmapUnlockBits(GpBitmap *b, BitmapData *d) { p_GdipBitmapUnlockBits fn = RESOLVE(GdipBitmapUnlockBits); return fn ? fn(b, d) : GenericError; }
GpStatus WINAPI GdipCloneImage(GpImage *i, GpImage **c) { p_GdipCloneImage fn = RESOLVE(GdipCloneImage); return fn ? fn(i, c) : GenericError; }
GpStatus WINAPI GdipDrawImageI(GpGraphics *g, GpImage *i, INT x, INT y) { p_GdipDrawImageI fn = RESOLVE(GdipDrawImageI); return fn ? fn(g, i, x, y) : GenericError; }
GpStatus WINAPI GdipCreateBitmapFromScan0(INT w, INT h, INT stride, PixelFormat fmt, BYTE *scan, GpBitmap **b) { p_GdipCreateBitmapFromScan0 fn = RESOLVE(GdipCreateBitmapFromScan0); return fn ? fn(w, h, stride, fmt, scan, b) : GenericError; }
GpStatus WINAPI GdipGetImageWidth(GpImage *i, UINT *w) { p_GdipGetImageWidth fn = RESOLVE(GdipGetImageWidth); return fn ? fn(i, w) : GenericError; }
GpStatus WINAPI GdipGetImagePalette(GpImage *i, ColorPalette *p, INT s) { p_GdipGetImagePalette fn = RESOLVE(GdipGetImagePalette); return fn ? fn(i, p, s) : GenericError; }
GpStatus WINAPI GdipDeleteGraphics(GpGraphics *g) { p_GdipDeleteGraphics fn = RESOLVE(GdipDeleteGraphics); return fn ? fn(g) : GenericError; }
GpStatus WINAPI GdipGetImageGraphicsContext(GpImage *i, GpGraphics **g) { p_GdipGetImageGraphicsContext fn = RESOLVE(GdipGetImageGraphicsContext); return fn ? fn(i, g) : GenericError; }
GpStatus WINAPI GdipCreateBitmapFromStream(IStream *s, GpBitmap **b) { p_GdipCreateBitmapFromStream fn = RESOLVE(GdipCreateBitmapFromStream); return fn ? fn(s, b) : GenericError; }
VOID WINAPI GdipFree(VOID *p) { p_GdipFree fn = RESOLVE(GdipFree); if (fn) fn(p); }
GpStatus WINAPI GdipGetImagePixelFormat(GpImage *i, PixelFormat *f) { p_GdipGetImagePixelFormat fn = RESOLVE(GdipGetImagePixelFormat); return fn ? fn(i, f) : GenericError; }
GpStatus WINAPI GdipDisposeImage(GpImage *i) { p_GdipDisposeImage fn = RESOLVE(GdipDisposeImage); return fn ? fn(i) : GenericError; }
VOID *WINAPI GdipAlloc(size_t s) { p_GdipAlloc fn = RESOLVE(GdipAlloc); return fn ? fn(s) : NULL; }
GpStatus WINAPI GdipBitmapLockBits(GpBitmap *b, GDIPCONST Rect *r, UINT flags, PixelFormat fmt, BitmapData *d) { p_GdipBitmapLockBits fn = RESOLVE(GdipBitmapLockBits); return fn ? fn(b, r, flags, fmt, d) : GenericError; }
