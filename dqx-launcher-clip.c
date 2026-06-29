/*
 * DQX updater redraw workaround.
 *
 * Build (Debian/Ubuntu package: gcc-mingw-w64-i686):
 *   i686-w64-mingw32-gcc -Os -s -nostdlib \
 *     -Wl,--subsystem,windows -Wl,--entry,_WinMainCRTStartup@0 \
 *     -Wl,--no-insert-timestamp -o dqx-launcher-clip.exe \
 *     dqx-launcher-clip.c -luser32 -lkernel32
 *
 * Public domain (Unlicense). NO WARRANTY. See UNLICENSE.
 */

#define UNICODE
#include <windows.h>

static HWND find_visible_progress(HWND main)
{
    static const WCHAR progress_class[] = L"msctls_progress32";
    HWND progress = FindWindowExW(main, NULL, progress_class, NULL);

    if (progress && (GetWindowLongPtrW(progress, GWL_STYLE) & WS_VISIBLE))
        return progress;
    return NULL;
}

void WINAPI WinMainCRTStartup(void)
{
    static const WCHAR main_class[] = L"DQXLauncher.MainWindow";
    HWND main = NULL;
    DWORD waited;

    /* The same HWND is used for the pre-launcher H&S screen. Changing its
     * style that early breaks that screen, so wait for both the normal
     * WS_VISIBLE transition and the updater's visible progress child. */
    for (waited = 0; waited < 120000; waited += 20)
    {
        main = FindWindowW(main_class, NULL);
        if (main && (GetWindowLongPtrW(main, GWL_STYLE) & WS_VISIBLE) &&
            find_visible_progress(main))
            break;
        Sleep(20);
    }

    if (!main || waited >= 120000) ExitProcess(0); /* normal launcher */

    SetWindowLongPtrW(main, GWL_STYLE,
                      GetWindowLongPtrW(main, GWL_STYLE) | WS_CLIPCHILDREN);

    /* DQX's normal launcher intentionally paints through child rectangles,
     * so the workaround must only live for updater mode. */
    while (IsWindow(main))
    {
        if (!find_visible_progress(main))
        {
            SetWindowLongPtrW(main, GWL_STYLE,
                              GetWindowLongPtrW(main, GWL_STYLE) &
                              ~WS_CLIPCHILDREN);
            break;
        }
        Sleep(50);
    }
    ExitProcess(0);
}
