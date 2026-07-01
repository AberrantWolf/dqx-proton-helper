/*
 * DQXLauncher early-window redraw probe/workaround for CrossOver macOS.
 *
 * Build:
 *   i686-w64-mingw32-gcc -Os -municode -o build/launcher-redraw.exe \
 *     tools/launcher-redraw.c -lgdi32 -luser32 -lkernel32
 *
 * DQXLauncher briefly creates a visible 640x480 SS_BITMAP static control for
 * the health-and-safety warning before the normal launcher UI. On CrossOver's
 * mac driver that child HWND can exist without its bitmap ever being presented.
 * This helper starts before DQXBoot, watches for the DQXLauncher process, and
 * aggressively invalidates the launcher parent/children during that handoff.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <tlhelp32.h>
#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>

#ifndef SS_TYPEMASK
#define SS_TYPEMASK 0x0000001fL
#endif

#define MAX_PIDS 32
#define HS_BITMAP_ID 164

static const WCHAR launcher_path[] =
    L"C:\\Program Files (x86)\\SquareEnix\\DRAGON QUEST X\\Boot\\DQXLauncher.exe";

static FILE *log_file;
static HBITMAP warning_bitmap;
static LONG warning_width = 640;
static LONG warning_height = 480;

static void log_line(const WCHAR *fmt, ...)
{
    va_list ap;
    SYSTEMTIME st;

    if (!log_file) {
        log_file = _wfopen(L"C:\\users\\Public\\dqx-launcher-redraw.log", L"a");
        if (!log_file) return;
    }

    GetLocalTime(&st);
    fwprintf(log_file, L"%02u:%02u:%02u.%03u ",
             st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_start(ap, fmt);
    vfwprintf(log_file, fmt, ap);
    va_end(ap);
    fputwc(L'\n', log_file);
    fflush(log_file);
}

static int collect_launcher_pids(DWORD *pids, int max_pids)
{
    HANDLE snap;
    PROCESSENTRY32W pe;
    int count = 0;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;

    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do {
            if (!_wcsicmp(pe.szExeFile, L"DQXLauncher.exe") && count < max_pids) {
                pids[count++] = pe.th32ProcessID;
            }
        } while (Process32NextW(snap, &pe));
    }

    CloseHandle(snap);
    return count;
}

static int pid_is_launcher(DWORD pid, const DWORD *pids, int count)
{
    int i;

    for (i = 0; i < count; ++i) {
        if (pids[i] == pid) return 1;
    }
    return 0;
}

static void describe_window(HWND hwnd, WCHAR *buf, int len)
{
    WCHAR cls[128], text[128];
    RECT r;
    DWORD pid = 0;
    LONG_PTR style, exstyle;

    cls[0] = 0;
    text[0] = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    GetClassNameW(hwnd, cls, sizeof(cls) / sizeof(cls[0]));
    GetWindowTextW(hwnd, text, sizeof(text) / sizeof(text[0]));
    GetWindowRect(hwnd, &r);
    style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    exstyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

    _snwprintf(buf, len,
               L"hwnd=%p pid=%lu class=\"%ls\" visible=%d rect=(%ld,%ld)-(%ld,%ld) style=0x%08lx ex=0x%08lx text=\"%ls\"",
               hwnd, (unsigned long)pid, cls, IsWindowVisible(hwnd),
               r.left, r.top, r.right, r.bottom,
               (unsigned long)style, (unsigned long)exstyle, text);
    buf[len - 1] = 0;
}

struct find_child_ctx {
    HWND child;
};

static BOOL CALLBACK find_hs_child_proc(HWND hwnd, LPARAM lparam)
{
    struct find_child_ctx *ctx = (struct find_child_ctx *)lparam;
    WCHAR cls[128];
    RECT r;
    LONG_PTR style;
    LONG width, height;

    GetClassNameW(hwnd, cls, sizeof(cls) / sizeof(cls[0]));
    if (_wcsicmp(cls, L"Static")) return TRUE;

    style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if ((style & SS_TYPEMASK) != SS_BITMAP) return TRUE;
    if (!IsWindowVisible(hwnd)) return TRUE;

    GetWindowRect(hwnd, &r);
    width = r.right - r.left;
    height = r.bottom - r.top;
    if (width < 600 || width > 680 || height < 440 || height > 520) return TRUE;

    ctx->child = hwnd;
    return FALSE;
}

static HWND find_hs_child(HWND parent)
{
    struct find_child_ctx ctx;

    ctx.child = NULL;
    EnumChildWindows(parent, find_hs_child_proc, (LPARAM)&ctx);
    return ctx.child;
}

struct find_parent_ctx {
    const DWORD *pids;
    int pid_count;
    HWND parent;
    HWND child;
};

static BOOL CALLBACK find_parent_proc(HWND hwnd, LPARAM lparam)
{
    struct find_parent_ctx *ctx = (struct find_parent_ctx *)lparam;
    DWORD pid = 0;
    HWND child;

    GetWindowThreadProcessId(hwnd, &pid);
    if (!pid_is_launcher(pid, ctx->pids, ctx->pid_count)) return TRUE;
    if (!IsWindowVisible(hwnd)) return TRUE;

    child = find_hs_child(hwnd);
    if (!child) return TRUE;

    ctx->parent = hwnd;
    ctx->child = child;
    return FALSE;
}

static int repaint_pair(HWND parent, HWND child)
{
    UINT flags = RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_INTERNALPAINT;
    DWORD_PTR image = 0;

    if (!IsWindow(parent)) return 0;

    if (IsWindow(child)) {
        if (SendMessageTimeoutW(child, STM_GETIMAGE, IMAGE_BITMAP, 0,
                                SMTO_ABORTIFHUNG, 20, &image) && image) {
            SendMessageTimeoutW(child, STM_SETIMAGE, IMAGE_BITMAP, (LPARAM)image,
                                SMTO_ABORTIFHUNG, 20, NULL);
        }
        SetWindowPos(child, NULL, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        InvalidateRect(child, NULL, TRUE);
        RedrawWindow(child, NULL, NULL, flags);
        PostMessageW(child, WM_PAINT, 0, 0);
    }

    SetWindowPos(parent, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                 SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
    InvalidateRect(parent, NULL, TRUE);
    RedrawWindow(parent, NULL, NULL, flags);
    PostMessageW(parent, WM_PAINT, 0, 0);
    return 1;
}

static int load_warning_bitmap(void)
{
    HMODULE launcher;
    BITMAP bitmap;

    if (warning_bitmap) return 1;

    launcher = LoadLibraryExW(launcher_path, NULL, LOAD_LIBRARY_AS_DATAFILE);
    if (!launcher) {
        log_line(L"LoadLibraryEx failed for %ls err=%lu", launcher_path, GetLastError());
        return 0;
    }

    warning_bitmap = (HBITMAP)LoadImageW(launcher, MAKEINTRESOURCEW(HS_BITMAP_ID),
                                         IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION);
    if (!warning_bitmap) {
        log_line(L"LoadImage BITMAP/%u failed err=%lu", HS_BITMAP_ID, GetLastError());
        FreeLibrary(launcher);
        return 0;
    }

    if (GetObjectW(warning_bitmap, sizeof(bitmap), &bitmap) == sizeof(bitmap)) {
        warning_width = bitmap.bmWidth;
        warning_height = bitmap.bmHeight;
    }

    log_line(L"loaded BITMAP/%u size=%ldx%ld", HS_BITMAP_ID,
             warning_width, warning_height);
    FreeLibrary(launcher);
    return 1;
}

static LRESULT CALLBACK overlay_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg) {
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        HDC mem = CreateCompatibleDC(dc);
        HGDIOBJ old = SelectObject(mem, warning_bitmap);
        RECT r;

        GetClientRect(hwnd, &r);
        StretchBlt(dc, 0, 0, r.right - r.left, r.bottom - r.top,
                   mem, 0, 0, warning_width, warning_height, SRCCOPY);
        SelectObject(mem, old);
        DeleteDC(mem);
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_DESTROY:
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static HWND show_warning_overlay(HINSTANCE inst, RECT *target)
{
    static const WCHAR cls[] = L"DQXLauncher.HSOverlay";
    WNDCLASSW wc;
    HWND hwnd;
    LONG width = target->right - target->left;
    LONG height = target->bottom - target->top;

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = overlay_proc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.lpszClassName = cls;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassW(&wc);

    if (width <= 0) width = warning_width;
    if (height <= 0) height = warning_height;

    hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
                           cls, L"", WS_POPUP,
                           target->left, target->top, width, height,
                           NULL, NULL, inst, NULL);
    if (!hwnd) {
        log_line(L"CreateWindowEx overlay failed err=%lu", GetLastError());
        return NULL;
    }

    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    UpdateWindow(hwnd);
    log_line(L"overlay shown hwnd=%p rect=(%ld,%ld)-(%ld,%ld)",
             hwnd, target->left, target->top, target->right, target->bottom);
    return hwnd;
}

static void pump_overlay(HWND overlay, DWORD duration_ms)
{
    DWORD start = GetTickCount();
    MSG msg;

    while (IsWindow(overlay) && GetTickCount() - start < duration_ms) {
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        InvalidateRect(overlay, NULL, FALSE);
        Sleep(20);
    }

    if (IsWindow(overlay)) DestroyWindow(overlay);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR cmdline, int show)
{
    DWORD pids[MAX_PIDS];
    DWORD waited;
    HWND parent = NULL, child = NULL;
    HWND overlay = NULL;
    RECT parent_rect;
    WCHAR desc[512];
    int saw_launcher = 0;
    int repaints = 0;

    (void)inst;
    (void)prev;
    (void)cmdline;
    (void)show;

    log_line(L"start");

    for (waited = 0; waited < 15000; waited += 20) {
        struct find_parent_ctx ctx;
        int pid_count = collect_launcher_pids(pids, MAX_PIDS);

        if (pid_count > 0 && !saw_launcher) {
            saw_launcher = 1;
            log_line(L"found DQXLauncher.exe pid_count=%d", pid_count);
        }

        ctx.pids = pids;
        ctx.pid_count = pid_count;
        ctx.parent = NULL;
        ctx.child = NULL;

        if (pid_count > 0) {
            EnumWindows(find_parent_proc, (LPARAM)&ctx);
            if (ctx.parent && ctx.child) {
                parent = ctx.parent;
                child = ctx.child;
                describe_window(parent, desc, sizeof(desc) / sizeof(desc[0]));
                log_line(L"candidate parent %ls", desc);
                describe_window(child, desc, sizeof(desc) / sizeof(desc[0]));
                log_line(L"candidate child  %ls", desc);
                break;
            }
        }

        Sleep(20);
    }

    if (!parent || !child) {
        log_line(L"no H&S bitmap child found after %lu ms; saw_launcher=%d",
                 (unsigned long)waited, saw_launcher);
        if (log_file) fclose(log_file);
        return 0;
    }

    GetWindowRect(parent, &parent_rect);
    if (load_warning_bitmap()) {
        overlay = show_warning_overlay(inst, &parent_rect);
    }

    for (waited = 0; waited < 4500 && IsWindow(parent); waited += 20) {
        if (repaint_pair(parent, child)) ++repaints;
        if (overlay) {
            MSG msg;
            while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        Sleep(20);
    }

    if (overlay) pump_overlay(overlay, 2800);

    log_line(L"done repaints=%d", repaints);
    if (warning_bitmap) DeleteObject(warning_bitmap);
    if (log_file) fclose(log_file);
    return 0;
}
