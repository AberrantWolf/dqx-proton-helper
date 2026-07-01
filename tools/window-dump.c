/*
 * Dump visible Win32 windows and child controls for DQX launcher debugging.
 *
 * Build:
 *   i686-w64-mingw32-gcc -Os -municode -o window-dump.exe tools/window-dump.c -luser32
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>

#ifndef SS_TYPEMASK
#define SS_TYPEMASK 0x0000001fL
#endif

#ifndef LBS_NOTIFY
#define LBS_NOTIFY            0x0001L
#define LBS_SORT              0x0002L
#define LBS_NOREDRAW          0x0004L
#define LBS_MULTIPLESEL       0x0008L
#define LBS_OWNERDRAWFIXED    0x0010L
#define LBS_OWNERDRAWVARIABLE 0x0020L
#define LBS_HASSTRINGS        0x0040L
#define LBS_USETABSTOPS       0x0080L
#define LBS_NOINTEGRALHEIGHT  0x0100L
#define LBS_MULTICOLUMN       0x0200L
#define LBS_WANTKEYBOARDINPUT 0x0400L
#define LBS_EXTENDEDSEL       0x0800L
#define LBS_DISABLENOSCROLL   0x1000L
#define LBS_NODATA            0x2000L
#define LBS_NOSEL             0x4000L
#endif

static void print_wide(const WCHAR *s)
{
    char buf[1024];
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, sizeof(buf), NULL, NULL);
    if (n > 0) fputs(buf, stdout);
    else fputs("<utf8-failed>", stdout);
}

static LRESULT send_timeout(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam, DWORD timeout)
{
    DWORD_PTR result = 0;
    if (!SendMessageTimeoutW(hwnd, msg, wparam, lparam, SMTO_ABORTIFHUNG, timeout, &result)) {
        return LB_ERR;
    }
    return (LRESULT)result;
}

static BOOL send_timeout_result(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam,
                                DWORD timeout, DWORD flags, DWORD_PTR *result,
                                DWORD *last_error)
{
    SetLastError(0);
    *result = 0;
    if (SendMessageTimeoutW(hwnd, msg, wparam, lparam, flags, timeout, result)) {
        if (last_error) *last_error = 0;
        return TRUE;
    }
    if (last_error) *last_error = GetLastError();
    return FALSE;
}

static void get_text(HWND hwnd, WCHAR *buf, int len)
{
    LRESULT n;
    buf[0] = 0;
    n = SendMessageTimeoutW(hwnd, WM_GETTEXT, len, (LPARAM)buf,
                            SMTO_ABORTIFHUNG, 200, NULL);
    if (!n) GetWindowTextW(hwnd, buf, len);
}

static void print_flag(LONG_PTR style, LONG_PTR flag, const char *name, int *printed)
{
    if (style & flag) {
        printf("%s%s", *printed ? "," : "", name);
        *printed = 1;
    }
}

static int looks_wide_printable(const WCHAR *s, SIZE_T bytes)
{
    SIZE_T chars = bytes / sizeof(WCHAR);
    int good = 0, total = 0;
    SIZE_T i;

    for (i = 0; i < chars && s[i]; ++i) {
        WCHAR c = s[i];
        ++total;
        if ((c >= 0x20 && c < 0xd800) || c == L'\t' || c == L'\r' || c == L'\n') ++good;
    }
    return total >= 2 && good == total;
}

static void print_memory_string(HANDLE process, UINT_PTR addr, int depth, const char *label)
{
    BYTE bytes[160];
    SIZE_T got = 0;
    WCHAR wide[80];
    char narrow[160];
    WCHAR converted[160];
    int n;

    if (addr < 0x10000) return;
    if (!ReadProcessMemory(process, (LPCVOID)addr, bytes, sizeof(bytes) - 2, &got) || got < 4) return;
    bytes[got] = 0;
    bytes[got + 1] = 0;

    CopyMemory(wide, bytes, got < sizeof(wide) ? got : sizeof(wide));
    wide[(got < sizeof(wide) ? got : sizeof(wide)) / sizeof(WCHAR) - 1] = 0;
    if (looks_wide_printable(wide, got)) {
        for (int j = 0; j < depth; ++j) printf("  ");
        printf("%s utf16@0x%Ix=\"", label, addr);
        print_wide(wide);
        printf("\"\n");
        return;
    }

    CopyMemory(narrow, bytes, got < sizeof(narrow) ? got : sizeof(narrow));
    narrow[(got < sizeof(narrow) ? got : sizeof(narrow)) - 1] = 0;
    n = MultiByteToWideChar(932, MB_ERR_INVALID_CHARS, narrow, -1,
                            converted, sizeof(converted) / sizeof(converted[0]));
    if (n <= 0) {
        n = MultiByteToWideChar(CP_ACP, 0, narrow, -1,
                                converted, sizeof(converted) / sizeof(converted[0]));
    }
    if (n > 2 && looks_wide_printable(converted, n * sizeof(WCHAR))) {
        for (int j = 0; j < depth; ++j) printf("  ");
        printf("%s mb@0x%Ix=\"", label, addr);
        print_wide(converted);
        printf("\"\n");
    }
}

static void dump_item_memory(HANDLE process, UINT_PTR data, int depth)
{
    BYTE bytes[96];
    SIZE_T got = 0;
    DWORD *words = (DWORD *)bytes;
    SIZE_T word_count;

    if (!process || data < 0x10000) return;
    if (!ReadProcessMemory(process, (LPCVOID)data, bytes, sizeof(bytes), &got) || got < 4) return;

    for (int j = 0; j < depth; ++j) printf("  ");
    printf("itemData bytes@0x%Ix:", data);
    for (SIZE_T i = 0; i < got && i < 48; ++i) printf(" %02x", bytes[i]);
    printf("\n");

    print_memory_string(process, data, depth, "itemData");
    word_count = got / sizeof(DWORD);
    for (SIZE_T i = 0; i < word_count && i < 16; ++i) {
        UINT_PTR candidate = (UINT_PTR)words[i];
        if (candidate >= 0x10000 && candidate < 0x80000000) {
            char label[64];
            snprintf(label, sizeof(label), "itemData+0x%02Ix ptr", i * sizeof(DWORD));
            print_memory_string(process, candidate, depth, label);
        }
    }
}

static void dump_listbox(HWND hwnd, int depth, LONG_PTR style, DWORD pid)
{
    LRESULT count, cur_sel, top_index, item_height;
    HANDLE process = NULL;
    int i, flags = 0;

    for (i = 0; i < depth; ++i) printf("  ");
    printf("listbox flags=");
    print_flag(style, LBS_NOTIFY, "NOTIFY", &flags);
    print_flag(style, LBS_SORT, "SORT", &flags);
    print_flag(style, LBS_NOREDRAW, "NOREDRAW", &flags);
    print_flag(style, LBS_MULTIPLESEL, "MULTIPLESEL", &flags);
    print_flag(style, LBS_OWNERDRAWFIXED, "OWNERDRAWFIXED", &flags);
    print_flag(style, LBS_OWNERDRAWVARIABLE, "OWNERDRAWVARIABLE", &flags);
    print_flag(style, LBS_HASSTRINGS, "HASSTRINGS", &flags);
    print_flag(style, LBS_USETABSTOPS, "USETABSTOPS", &flags);
    print_flag(style, LBS_NOINTEGRALHEIGHT, "NOINTEGRALHEIGHT", &flags);
    print_flag(style, LBS_MULTICOLUMN, "MULTICOLUMN", &flags);
    print_flag(style, LBS_WANTKEYBOARDINPUT, "WANTKEYBOARDINPUT", &flags);
    print_flag(style, LBS_EXTENDEDSEL, "EXTENDEDSEL", &flags);
    print_flag(style, LBS_DISABLENOSCROLL, "DISABLENOSCROLL", &flags);
    print_flag(style, LBS_NODATA, "NODATA", &flags);
    print_flag(style, LBS_NOSEL, "NOSEL", &flags);
    if (!flags) printf("(none)");

    count = send_timeout(hwnd, LB_GETCOUNT, 0, 0, 500);
    cur_sel = send_timeout(hwnd, LB_GETCURSEL, 0, 0, 500);
    top_index = send_timeout(hwnd, LB_GETTOPINDEX, 0, 0, 500);
    item_height = send_timeout(hwnd, LB_GETITEMHEIGHT, 0, 0, 500);
    printf(" count=%ld curSel=%ld top=%ld itemHeight=%ld\n",
           (long)count, (long)cur_sel, (long)top_index, (long)item_height);

    if (count == LB_ERR || count < 0) return;
    if (count > 32) count = 32;
    process = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);

    for (i = 0; i < count; ++i) {
        LRESULT len, data, sel;
        RECT item_rect;
        WCHAR item_text[512];
        item_text[0] = 0;
        SetRectEmpty(&item_rect);

        len = send_timeout(hwnd, LB_GETTEXTLEN, (WPARAM)i, 0, 500);
        data = send_timeout(hwnd, LB_GETITEMDATA, (WPARAM)i, 0, 500);
        sel = send_timeout(hwnd, LB_GETSEL, (WPARAM)i, 0, 500);
        send_timeout(hwnd, LB_GETITEMRECT, (WPARAM)i, (LPARAM)&item_rect, 500);
        if (len != LB_ERR && len >= 0 && len < 511) {
            send_timeout(hwnd, LB_GETTEXT, (WPARAM)i, (LPARAM)item_text, 500);
        }

        for (int j = 0; j < depth; ++j) printf("  ");
        printf("item[%d] len=%ld data=0x%Ix sel=%ld rect=(%ld,%ld)-(%ld,%ld) text=\"",
               i, (long)len, (UINT_PTR)data, (long)sel,
               item_rect.left, item_rect.top, item_rect.right, item_rect.bottom);
        print_wide(item_text);
        printf("\"\n");
        dump_item_memory(process, (UINT_PTR)data, depth + 1);
    }

    if (process) CloseHandle(process);
}

static void dump_window(HWND hwnd, int depth)
{
    WCHAR cls[256], text[512];
    RECT r;
    DWORD pid = 0;
    LONG_PTR style, exstyle;
    int i;

    GetWindowThreadProcessId(hwnd, &pid);
    GetClassNameW(hwnd, cls, 256);
    get_text(hwnd, text, 512);
    GetWindowRect(hwnd, &r);
    style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    exstyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

    for (i = 0; i < depth; ++i) printf("  ");
    printf("hwnd=%p pid=%lu class=", hwnd, (unsigned long)pid);
    print_wide(cls);
    printf(" visible=%d enabled=%d rect=(%ld,%ld)-(%ld,%ld) style=0x%08lx ex=0x%08lx text=\"",
           IsWindowVisible(hwnd), IsWindowEnabled(hwnd),
           r.left, r.top, r.right, r.bottom,
           (unsigned long)style, (unsigned long)exstyle);
    print_wide(text);
    printf("\"\n");

    if (!wcscmp(cls, L"Static") && ((style & SS_TYPEMASK) == SS_BITMAP)) {
        DWORD_PTR image = 0;
        DWORD last_error = 0;
        BOOL ok = send_timeout_result(hwnd, STM_GETIMAGE, IMAGE_BITMAP, 0, 500,
                                      SMTO_NORMAL, &image, &last_error);
        BITMAP bm;

        for (i = 0; i <= depth; ++i) printf("  ");
        printf("static image-ok=%d image=0x%Ix", ok, (UINT_PTR)image);
        if (!ok) {
            printf(" lastError=%lu", (unsigned long)last_error);
        }
        if (ok && image && GetObjectW((HBITMAP)image, sizeof(bm), &bm) == sizeof(bm)) {
            printf(" bitmap=%ldx%ld bpp=%u", bm.bmWidth, bm.bmHeight, bm.bmBitsPixel);
        }
        printf("\n");
    }

    if (wcscmp(cls, L"ListBox") == 0) {
        dump_listbox(hwnd, depth + 1, style, pid);
    }
}

static BOOL CALLBACK enum_child_proc(HWND hwnd, LPARAM lparam)
{
    int depth = (int)lparam;
    dump_window(hwnd, depth);
    EnumChildWindows(hwnd, enum_child_proc, depth + 1);
    return TRUE;
}

static BOOL CALLBACK enum_top_proc(HWND hwnd, LPARAM lparam)
{
    WCHAR cls[256], text[512];
    (void)lparam;
    GetClassNameW(hwnd, cls, 256);
    get_text(hwnd, text, 512);

    if (IsWindowVisible(hwnd) || wcsstr(cls, L"DQX") || wcsstr(text, L"DQX") ||
        wcsstr(text, L"ドラゴンクエスト")) {
        dump_window(hwnd, 0);
        EnumChildWindows(hwnd, enum_child_proc, 1);
    }
    return TRUE;
}

int wmain(void)
{
    EnumWindows(enum_top_proc, 0);
    return 0;
}
