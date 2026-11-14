//
//  Identity.h
//  FaceNow
//

#pragma once
#include <windows.h>
#include <string>
inline constexpr wchar_t SourceId[] = L"{C1EF1269-DBA1-473B-BD21-7F3695635A11}";
inline constexpr wchar_t CameraName[] = L"FaceNow 虚拟摄像头";
inline constexpr wchar_t LegacyCameraName[] = L"FaceNow - Xmax Virtual Camera";
inline constexpr wchar_t UserKey[] = L"Software\\XMAX.AI\\FaceNow\\VirtualCamera";
inline constexpr wchar_t ClassKey[] = L"Software\\Classes\\CLSID\\{C1EF1269-DBA1-473B-BD21-7F3695635A11}\\InProcServer32";
inline constexpr wchar_t SourceFile[] = L"FaceNow.CameraSource.dll";
inline constexpr GUID DirectShowId = {0xf11e1479, 0x1712, 0x44c0, {0xbc, 0xb1, 0x80, 0x4d, 0x18, 0x6d, 0x79, 0x47}};
inline constexpr wchar_t DirectShowClassKey[] = L"Software\\Classes\\CLSID\\{F11E1479-1712-44C0-BCB1-804D186D7947}\\InProcServer32";

inline std::wstring DirectShowEndpoint(DWORD session) {
    return L"FaceNow.DirectShow." + std::to_wstring(session);
}
