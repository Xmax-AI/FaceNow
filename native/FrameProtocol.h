#pragma once
#include <windows.h>
#include <cstdint>
#include <wincrypt.h>
#include <string>
#include <algorithm>
#include <cwctype>

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
inline std::wstring PipeName(std::wstring link) {
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
