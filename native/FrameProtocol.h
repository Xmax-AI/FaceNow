#pragma once
#include <windows.h>
#include <cstdint>
#include <wincrypt.h>
#include <string>
#include <algorithm>
#include <cwctype>
#include <cfgmgr32.h>
#include <vector>

namespace FaceNowFrames {
constexpr uint32_t Magic = 0x314e4346; // FCN1, little endian
constexpr uint32_t Version = 1;
constexpr uint32_t MaxBytes = 64 * 1024 * 1024;
#pragma pack(push, 1)
struct Request { uint32_t magic = Magic, version = Version; };
struct Header {
    uint32_t magic = Magic, version = Version;
    uint32_t width = 0, height = 0, stride = 0, length = 0;
    int64_t timestampMicroseconds = 0;
    BYTE session[16]{};
    uint64_t sequence = 0;
    uint32_t active = 0, reserved = 0;
};
#pragma pack(pop)
static_assert(sizeof(Header) == 64);
inline constexpr GUID VideoCameraCategory = {0xe5323777, 0xf976, 0x4f5b, {0x9b, 0x55, 0xb9, 0x46, 0x99, 0xc4, 0x6e, 0x44}};
inline constexpr GUID CaptureCategory = {0x65e8773d, 0x8f56, 0x11d0, {0xa3, 0xb9, 0x00, 0xa0, 0xc9, 0x22, 0x31, 0x96}};

// Symbolic links are opaque. Resolve their owning device through Configuration
// Manager, then ask Windows for that device's interface in the requested category.
// DirectShow supplies KSCATEGORY_CAPTURE; MF enumeration uses VIDEO_CAMERA.
inline std::wstring DeviceInterfaceLink(const std::wstring& link, GUID category) {
    constexpr DEVPROPKEY instanceKey = {{0x78c34fc8, 0x104a, 0x4aca, {0x9e, 0xa4, 0x52, 0x4d, 0x52, 0x99, 0x6e, 0x57}}, 256};
    wchar_t instance[MAX_DEVICE_ID_LEN]{};
    DEVPROPTYPE type = 0; ULONG bytes = sizeof(instance);
    if (CM_Get_Device_Interface_PropertyW(link.c_str(), &instanceKey, &type,
        reinterpret_cast<PBYTE>(instance), &bytes, 0) != CR_SUCCESS ||
        type != DEVPROP_TYPE_STRING || bytes < sizeof(wchar_t) || bytes > sizeof(instance) ||
        bytes % sizeof(wchar_t) || instance[bytes / sizeof(wchar_t) - 1] != L'\0') return link;
    ULONG characters = 0;
    if (CM_Get_Device_Interface_List_SizeW(&characters, &category, instance,
        CM_GET_DEVICE_INTERFACE_LIST_PRESENT) != CR_SUCCESS || characters < 2 || characters > 65536) return link;
    std::vector<wchar_t> interfaces(characters, L'\0');
    if (CM_Get_Device_Interface_ListW(&category, instance, interfaces.data(), characters,
        CM_GET_DEVICE_INTERFACE_LIST_PRESENT) != CR_SUCCESS) return link;
    auto end = std::find(interfaces.begin(), interfaces.end(), L'\0');
    if (end == interfaces.begin() || end == interfaces.end()) return link;
    return {interfaces.begin(), end};
}

inline std::wstring PipeName(std::wstring link) {
    // The publisher hashes the MF camera link. Normalize DirectShow aliases to
    // the same device interface without parsing or rewriting symbolic links.
    link = DeviceInterfaceLink(link, VideoCameraCategory);
    std::transform(link.begin(), link.end(), link.begin(), [](wchar_t c) { return (wchar_t)towlower(c); });
    DWORD length = sizeof(BYTE) * 32; BYTE hash[32];
    // Hash UTF-16LE bytes identically in the native source and managed publisher.
    if (!CryptHashCertificate2(L"SHA256", 0, nullptr, reinterpret_cast<const BYTE*>(link.data()),
        (DWORD)(link.size() * sizeof(wchar_t)), hash, &length)) return {};
    std::wstring name = L"\\\\.\\pipe\\FaceNow.Camera.v1.";
    for (BYTE c : hash) { name += L"0123456789abcdef"[c >> 4]; name += L"0123456789abcdef"[c & 15]; }
    return name;
}
}
