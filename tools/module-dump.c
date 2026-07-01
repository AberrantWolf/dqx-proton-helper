/*
 * Dump loaded modules for DQX processes.
 *
 * Build:
 *   i686-w64-mingw32-gcc -Os -municode -o build/module-dump.exe tools/module-dump.c -lpsapi
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>

static void print_wide(const WCHAR *s)
{
    char buf[2048];
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, sizeof(buf), NULL, NULL);
    if (n > 0) fputs(buf, stdout);
    else fputs("<utf8-failed>", stdout);
}

static int is_dqx_process(const WCHAR *name)
{
    return wcsstr(name, L"DQX") || wcsstr(name, L"dqx");
}

static void dump_modules(DWORD pid, const WCHAR *proc_name)
{
    HANDLE snap;
    MODULEENTRY32W me;

    printf("process pid=%lu name=", (unsigned long)pid);
    print_wide(proc_name);
    printf("\n");

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snap == INVALID_HANDLE_VALUE) {
        printf("  module snapshot failed gle=%lu\n", (unsigned long)GetLastError());
        return;
    }

    ZeroMemory(&me, sizeof(me));
    me.dwSize = sizeof(me);
    if (Module32FirstW(snap, &me)) {
        do {
            printf("  base=%p size=%lu name=", me.modBaseAddr, (unsigned long)me.modBaseSize);
            print_wide(me.szModule);
            printf(" path=");
            print_wide(me.szExePath);
            printf("\n");
        } while (Module32NextW(snap, &me));
    }
    CloseHandle(snap);
}

int wmain(void)
{
    HANDLE snap;
    PROCESSENTRY32W pe;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 1;

    ZeroMemory(&pe, sizeof(pe));
    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do {
            if (is_dqx_process(pe.szExeFile)) {
                dump_modules(pe.th32ProcessID, pe.szExeFile);
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return 0;
}
