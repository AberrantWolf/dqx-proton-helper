/*
 * Minimal reproducer for Wine's managed X11 first-map surface loss.
 *
 * The window is painted synchronously and then the UI thread sleeps without
 * pumping messages, matching the behavior that exposes the DQX pre-launch
 * health-and-safety window failure.
 *
 * Public domain (Unlicense). NO WARRANTY. See ../../UNLICENSE.
 */

#include <windows.h>

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg)
    {
    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        RECT rect;
        HBRUSH background = CreateSolidBrush(RGB(24, 48, 96));
        HBRUSH marker = CreateSolidBrush(RGB(186, 186, 186));
        HDC dc = BeginPaint(hwnd, &ps);

        GetClientRect(hwnd, &rect);
        FillRect(dc, &rect, background);
        SetRect(&rect, 400, 200, 600, 400);
        FillRect(dc, &rect, marker);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        TextOutW(dc, 40, 40, L"Wine first-map surface test", 27);

        DeleteObject(marker);
        DeleteObject(background);
        EndPaint(hwnd, &ps);
        return 0;
    }
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, WCHAR *command_line, int show)
{
    static const WCHAR class_name[] = L"WineFirstMapSurfaceTest";
    WNDCLASSW wc = {0};
    HWND hwnd;
    int x = (GetSystemMetrics(SM_CXSCREEN) - 640) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - 480) / 2;

    (void)previous;
    (void)command_line;
    (void)show;

    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.lpszClassName = class_name;
    if (!RegisterClassW(&wc)) return 1;

    hwnd = CreateWindowExW(WS_EX_APPWINDOW, class_name, L"Wine first-map surface test",
                           WS_POPUP, x, y, 640, 480, NULL, NULL, instance, NULL);
    if (!hwnd) return 2;

    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);
    Sleep(3000);
    DestroyWindow(hwnd);
    UnregisterClassW(class_name, instance);
    return 0;
}
