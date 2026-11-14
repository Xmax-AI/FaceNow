//
//  SourceDiagnostics.h
//  FaceNow
//

#pragma once
#include <windows.h>
#include <cstdio>
#include <string>

// Metadata only. The service cannot write into the interactive user's profile;
// use the Application event log and let FaceNow copy our records into its log.
inline void SourceDiagnostic(const wchar_t* stage, DWORD code, LONG pitch, UINT width, UINT height,
    const std::wstring& pipeName) {
    wchar_t message[512]{};
    const auto endpoint = pipeName.size() >= 16 ? pipeName.substr(pipeName.size() - 16) : L"none";
    swprintf_s(message, L"FaceNow source build=20261030.2 pid=%lu stage=%s code=0x%08lX pitch=%ld size=%ux%u endpoint=%s",
        GetCurrentProcessId(), stage, code, pitch, width, height, endpoint.c_str());
    OutputDebugStringW(message);
    if (auto log = RegisterEventSourceW(nullptr, L"FaceNow.CameraSource")) {
        const wchar_t* strings[] = {message};
        ReportEventW(log, EVENTLOG_INFORMATION_TYPE, 0, 1000, nullptr, 1, 0, strings, nullptr);
        DeregisterEventSource(log);
    }
}
