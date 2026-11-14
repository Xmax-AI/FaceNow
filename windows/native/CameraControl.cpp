//
//  CameraControl.cpp
//  FaceNow
//

// FaceNow's native, architecture-matched camera installer and diagnostic host.
#include <windows.h>
#ifdef FACENOW_DIRECTSHOW_BACKEND
#include <dshow.h>
#include <shellapi.h>
#else
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mfvirtualcamera.h>
#include <mferror.h>
#endif
#include <wrl/client.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <filesystem>
#include <fstream>
#include <vector>
#include <string>
#include <string_view>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <algorithm>
#include "Identity.h"
#ifndef FACENOW_DIRECTSHOW_BACKEND
#include "FrameProtocol.h"
#endif

using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;
struct Failure { HRESULT code; std::string operation; };
void Check(HRESULT result, const char* operation) { if (FAILED(result)) throw Failure{result, operation}; }
std::string Utf8(const std::wstring& text) {
    if (text.empty()) return {};
    int count = WideCharToMultiByte(CP_UTF8, 0, text.data(), (int)text.size(), nullptr, 0, nullptr, nullptr);
    std::string value(count, 0); WideCharToMultiByte(CP_UTF8, 0, text.data(), (int)text.size(), value.data(), count, nullptr, nullptr); return value;
}
std::string Json(const std::wstring& value) {
    std::ostringstream out; out << '"';
    for (unsigned char c : Utf8(value)) {
        if (c == '"' || c == '\\') out << '\\' << c;
        else if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (unsigned)c;
        else out << c;
    }
    out << '"'; return out.str();
}
std::wstring ReadString(HKEY root, const wchar_t* key, const wchar_t* name) {
    DWORD bytes = 0;
    auto code = RegGetValueW(root, key, name, RRF_RT_REG_SZ, nullptr, nullptr, &bytes);
    if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND) return {};
    Check(HRESULT_FROM_WIN32(code), "read registry");
    std::vector<wchar_t> text(bytes / sizeof(wchar_t) + 1);
    Check(HRESULT_FROM_WIN32(RegGetValueW(root, key, name, RRF_RT_REG_SZ, nullptr, text.data(), &bytes)), "read registry value");
    return text.data();
}
void WriteString(HKEY root, const wchar_t* key, const wchar_t* name, const std::wstring& value) {
    HKEY handle = nullptr;
    Check(HRESULT_FROM_WIN32(RegCreateKeyExW(root, key, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &handle, nullptr)), "open registry for installation");
    auto code = RegSetValueExW(handle, name, 0, REG_SZ, (const BYTE*)value.c_str(), (DWORD)((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(handle); Check(HRESULT_FROM_WIN32(code), "write registry");
}
fs::path ExecutablePath() { wchar_t path[32768]; auto length = GetModuleFileNameW(nullptr, path, 32768); if (!length || length >= 32768) throw Failure{E_FAIL,"locate camera helper"}; return path; }
fs::path Directory() { return ExecutablePath().parent_path(); }
std::wstring InstalledSource() {
#ifdef FACENOW_DIRECTSHOW_BACKEND
    return ReadString(HKEY_LOCAL_MACHINE, DirectShowClassKey, nullptr);
#else
    return ReadString(HKEY_LOCAL_MACHINE, ClassKey, nullptr);
#endif
}
bool IsCurrentSource(const fs::path& installed) {
    if (!fs::is_regular_file(installed)) return false;
    auto hashFile = [](const fs::path& path) {
        std::ifstream input(path, std::ios::binary);
        std::vector<BYTE> bytes((std::istreambuf_iterator<char>(input)), {});
        std::vector<BYTE> hash(32); DWORD size = (DWORD)hash.size();
        if (!input || bytes.empty() || bytes.size() > 32 * 1024 * 1024 ||
            !CryptHashCertificate2(L"SHA256", 0, nullptr, bytes.data(), (DWORD)bytes.size(), hash.data(), &size)) return std::vector<BYTE>{};
        return hash;
    };
    auto expected = hashFile(Directory() / SourceFile);
    return !expected.empty() && expected == hashFile(installed);
}
fs::path DeploySource() {
    // The elevated command accepts no path from the UI: only our sibling source DLL is installed.
    auto source = Directory() / SourceFile;
    std::ifstream input(source, std::ios::binary); if (!input) throw Failure{HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND),"locate camera DLL"};
    std::vector<BYTE> bytes((std::istreambuf_iterator<char>(input)), {});
    if (bytes.empty() || bytes.size() > 32 * 1024 * 1024) throw Failure{E_INVALIDARG,"validate camera DLL size"};
    BYTE hash[32]; DWORD hashSize = sizeof(hash);
    if (!CryptHashCertificate2(L"SHA256", 0, nullptr, bytes.data(), (DWORD)bytes.size(), hash, &hashSize)) throw Failure{HRESULT_FROM_WIN32(GetLastError()),"hash camera DLL"};
    std::wostringstream version; for (unsigned i = 0; i < 12; i++) version << std::hex << std::setw(2) << std::setfill(L'0') << (unsigned)hash[i];
    wchar_t* programFiles = nullptr; Check(SHGetKnownFolderPath(FOLDERID_ProgramFiles, 0, nullptr, &programFiles), "locate Program Files");
    fs::path destination = fs::path(programFiles) / L"FaceNow" / L"Camera" / version.str(); CoTaskMemFree(programFiles);
    fs::create_directories(destination);
    destination /= SourceFile;
    if (!CopyFileW(source.c_str(), destination.c_str(), TRUE) && GetLastError() != ERROR_FILE_EXISTS) throw Failure{HRESULT_FROM_WIN32(GetLastError()),"deploy camera DLL"};
    return destination;
}

#ifdef FACENOW_DIRECTSHOW_BACKEND
#include "DirectShow/DeviceControl.h"
#else
std::wstring DeviceLink() { return ReadString(HKEY_CURRENT_USER, UserKey, L"SymbolicLink"); }
ComPtr<IMFMediaSource> FindDevice(const std::wstring& link) {
    if (link.empty()) return {};
    ComPtr<IMFAttributes> attributes; Check(MFCreateAttributes(&attributes, 1), "create enumeration attributes");
    Check(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID), "set camera type");
    IMFActivate** devices = nullptr; UINT32 count = 0;
    Check(MFEnumDeviceSources(attributes.Get(), &devices, &count), "enumerate virtual camera");
    ComPtr<IMFActivate> match;
    for (UINT32 i = 0; i < count; ++i) {
        wchar_t* id = nullptr; UINT32 size = 0;
        if (SUCCEEDED(devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &id, &size))) {
            if (_wcsicmp(id, link.c_str()) == 0) match = devices[i];
            CoTaskMemFree(id);
        }
        devices[i]->Release();
    }
    CoTaskMemFree(devices);
    if (!match) return {};
    ComPtr<IMFMediaSource> source; Check(match->ActivateObject(IID_PPV_ARGS(&source)), "activate registered camera"); return source;
}
bool DeviceExists(const std::wstring& link, bool& nameCurrent, const wchar_t* expectedName = CameraName) {
    // Enumeration only: querying status must not activate a stream.
    ComPtr<IMFAttributes> attributes; Check(MFCreateAttributes(&attributes, 1), "create enumeration attributes");
    Check(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID), "set camera type");
    IMFActivate** devices = nullptr; UINT32 count = 0; bool found = false;
    Check(MFEnumDeviceSources(attributes.Get(), &devices, &count), "enumerate camera status");
    for (UINT32 i = 0; i < count; ++i) {
        bool match = link.empty();
        wchar_t* id = nullptr; UINT32 size = 0;
        if (!match && SUCCEEDED(devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &id, &size))) {
            match = _wcsicmp(id, link.c_str()) == 0;
            CoTaskMemFree(id);
        }
        if (match) {
            wchar_t* name = nullptr;
            if (SUCCEEDED(devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &size))) {
                nameCurrent |= std::wstring_view(name).rfind(expectedName, 0) == 0;
                CoTaskMemFree(name);
            }
            found |= !link.empty() || nameCurrent;
        }
        devices[i]->Release();
    }
    CoTaskMemFree(devices); return found;
}
void Status() {
    auto path = InstalledSource(); auto link = DeviceLink();
    bool installed = !path.empty() && fs::is_regular_file(path);
    bool nameCurrent = false;
    bool registered = !link.empty() && DeviceExists(link, nameCurrent);
    std::cout << "{\"installed\":" << (installed ? "true" : "false") << ",\"current\":" << (installed && IsCurrentSource(path) ? "true" : "false") << ",\"registered\":"
        << (registered ? "true" : "false") << ",\"nameCurrent\":" << (nameCurrent ? "true" : "false")
        << ",\"symbolicLink\":" << Json(link) << "}\n";
}
void Install() {
    auto destination = DeploySource();
    WriteString(HKEY_LOCAL_MACHINE, ClassKey, nullptr, destination.wstring());
    WriteString(HKEY_LOCAL_MACHINE, ClassKey, L"ThreadingModel", L"Both");
    std::cout << "{\"installed\":true}\n";
}
ComPtr<IMFVirtualCamera> OpenCamera(const wchar_t* name) {
    ComPtr<IMFVirtualCamera> camera;
    Check(MFCreateVirtualCamera(MFVirtualCameraType_SoftwareCameraSource, MFVirtualCameraLifetime_System,
        MFVirtualCameraAccess_CurrentUser, name, SourceId, nullptr, 0, &camera), "create virtual camera");
    return camera;
}
void RemoveCamera(const wchar_t* name) {
    auto camera = OpenCamera(name);
    HRESULT result = camera->Remove();
    camera->Shutdown();
    if (result == MF_E_INVALIDREQUEST) {
        bool namePresent = false;
        if (!DeviceExists({}, namePresent, name))
            return;
    }
    if (result != MF_E_NOT_FOUND && result != HRESULT_FROM_WIN32(ERROR_NOT_FOUND) &&
        result != HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND))
        Check(result, "remove virtual camera");
}
void Enable() {
    auto path = InstalledSource(); if (path.empty() || !fs::is_regular_file(path)) throw Failure{REGDB_E_CLASSNOTREG,"camera component not installed"};
    auto camera = OpenCamera(CameraName); Check(camera->Start(nullptr), "register virtual camera");
    wchar_t* link = nullptr; UINT32 size = 0;
    Check(camera->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &link, &size), "read camera symbolic link");
    std::wstring value(link); CoTaskMemFree(link); WriteString(HKEY_CURRENT_USER, UserKey, L"SymbolicLink", value);
    camera->Shutdown();
    // The friendly name is part of the Windows device identity. Publish the new link before retiring the old one.
    RemoveCamera(LegacyCameraName);
    Status();
}
void Remove() {
    RemoveCamera(CameraName);
    RemoveCamera(LegacyCameraName);
    auto code = RegDeleteKeyValueW(HKEY_CURRENT_USER, UserKey, L"SymbolicLink");
    if (code != ERROR_FILE_NOT_FOUND) Check(HRESULT_FROM_WIN32(code), "remove camera selection record");
    Status();
}
ComPtr<IMFMediaSource> LocalSource(const std::wstring& relayLink, bool lateLink) {
    static HMODULE module = LoadLibraryExW((Directory() / SourceFile).c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) throw Failure{HRESULT_FROM_WIN32(GetLastError()),"load local camera source"};
    auto factoryMethod = (HRESULT(__stdcall*)(REFCLSID,REFIID,void**))GetProcAddress(module, "DllGetClassObject");
    if (!factoryMethod) throw Failure{E_NOINTERFACE,"locate camera factory"};
    CLSID clsid; Check(CLSIDFromString(SourceId, &clsid), "parse camera identity");
    ComPtr<IClassFactory> factory; Check(factoryMethod(clsid, IID_PPV_ARGS(&factory)), "get camera factory");
    ComPtr<IMFActivate> activation; Check(factory->CreateInstance(nullptr, IID_PPV_ARGS(&activation)), "create camera activation");
    if (!relayLink.empty() && !lateLink)
        Check(activation->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, relayLink.c_str()), "set isolated relay test identity");
    ComPtr<IMFMediaSource> source; Check(activation->ActivateObject(IID_PPV_ARGS(&source)), "activate local camera source");
    if (lateLink) {
        ComPtr<IMFMediaSourceEx> extended;
        ComPtr<IMFAttributes> attributes;
        Check(source.As(&extended), "get extended camera source");
        Check(extended->GetSourceAttributes(&attributes), "get camera source attributes");
        Check(attributes->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, relayLink.c_str()), "set late relay test identity");
    }
    return source;
}
void Verify(bool local, const fs::path& screenshot, const std::wstring& relayLink = {}, bool lateLink = false) {
    auto source = local ? LocalSource(relayLink, lateLink) : FindDevice(DeviceLink());
    if (!source) throw Failure{MF_E_NOT_FOUND,"find FaceNow camera"};
    try {
        ComPtr<IMFAttributes> attributes; Check(MFCreateAttributes(&attributes, 2), "create reader attributes");
        Check(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE), "enable CPU video conversion");
        ComPtr<IMFSourceReader> reader; Check(MFCreateSourceReaderFromMediaSource(source.Get(), attributes.Get(), &reader), "create camera reader");
        Check(reader->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE), "select camera video stream");
        ComPtr<IMFMediaType> type; Check(MFCreateMediaType(&type), "create verification type");
        Check(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video), "set video major type");
        Check(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32), "set RGB output");
        Check(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, type.Get()), "negotiate RGB output");
        Check(reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &type), "get reader format");
        UINT32 width = 0, height = 0; Check(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width, &height), "get frame size");
        LONG stride = (LONG)MFGetAttributeUINT32(type.Get(), MF_MT_DEFAULT_STRIDE, width * 4);
        std::vector<BYTE> pixels; LONGLONG previous = -1; unsigned count = 0;
        while (count < 10) {
            DWORD flags = 0; LONGLONG time = 0; ComPtr<IMFSample> sample;
            Check(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, &time, &sample), "read camera sample");
            if (flags & MF_SOURCE_READERF_ERROR) throw Failure{E_FAIL,"camera reader error"};
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) throw Failure{E_FAIL,"camera stream ended"};
            if (!sample) continue;
            if (time <= previous) throw Failure{E_FAIL,"camera timestamps did not advance"}; previous = time;
            pixels.resize(width * height * 4);
            ComPtr<IMFMediaBuffer> buffer; Check(sample->GetBufferByIndex(0, &buffer), "read camera pixels");
            ComPtr<IMF2DBuffer2> surface;
            if (SUCCEEDED(buffer.As(&surface))) {
                BYTE* data = nullptr; BYTE* start = nullptr; DWORD length = 0; LONG pitch = 0;
                Check(surface->Lock2DSize(MF2DBuffer_LockFlags_Read, &data, &pitch, &start, &length), "lock camera surface");
                // Scanline 0 is the displayed top row even when RGB memory is bottom-up.
                for (UINT32 y = 0; y < height; y++) memcpy(pixels.data() + size_t(y) * width * 4, data + int64_t(y) * pitch, size_t(width) * 4);
                surface->Unlock2D();
            } else {
                Check(sample->ConvertToContiguousBuffer(&buffer), "read contiguous camera pixels");
                BYTE* data = nullptr; DWORD length = 0; Check(buffer->Lock(&data, nullptr, &length), "lock camera pixels");
                if (length < (uint64_t(abs(int64_t(stride))) * height)) { buffer->Unlock(); throw Failure{E_FAIL,"short video sample"}; }
                for (UINT32 y = 0; y < height; y++) memcpy(pixels.data() + size_t(y) * width * 4, data + (stride < 0 ? height - 1 - y : y) * abs(int64_t(stride)), size_t(width) * 4);
                buffer->Unlock();
            }
            count++;
        }
        BYTE low = 255, high = 0;
        for (size_t i = 0; i < pixels.size(); i++) if (i % 4 != 3) { low = (std::min)(low, pixels[i]); high = (std::max)(high, pixels[i]); }
        if (high - low < 40) {
            // A uniform image is valid only when it has the waiting canvas color.
            // Allow small RGB/NV12 round-trip differences; still reject unintended blank output.
            for (size_t i = 0; i < pixels.size(); i += 4)
                if (abs((int)pixels[i] - 244) > 4 || abs((int)pixels[i + 1] - 243) > 4 || abs((int)pixels[i + 2] - 241) > 4)
                    throw Failure{E_FAIL,"camera image is an unexpected uniform color"};
        }
        if (!screenshot.empty()) {
            BITMAPFILEHEADER file{}; file.bfType = 0x4d42; file.bfOffBits = sizeof(file) + sizeof(BITMAPINFOHEADER); file.bfSize = file.bfOffBits + (DWORD)pixels.size();
            BITMAPINFOHEADER image{}; image.biSize = sizeof(image); image.biWidth = width; image.biHeight = -(LONG)height; image.biPlanes = 1; image.biBitCount = 32; image.biSizeImage = (DWORD)pixels.size();
            std::ofstream output(screenshot, std::ios::binary); output.write((char*)&file, sizeof(file)); output.write((char*)&image,sizeof(image)); output.write((char*)pixels.data(),pixels.size());
            if (!output) throw Failure{E_FAIL,"save verification bitmap"};
        }
        reader.Reset(); source->Shutdown();
        std::cout << "{\"passed\":true,\"frames\":" << count << ",\"width\":" << width << ",\"height\":" << height << ",\"local\":" << (local ? "true" : "false") << "}\n";
    } catch (...) { source->Shutdown(); throw; }
}
#endif

int wmain(int argc, wchar_t** argv) {
#ifdef FACENOW_DIRECTSHOW_BACKEND
    HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
#else
    HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    HRESULT media = E_FAIL;
#endif
    int result = 0;
    try {
        Check(com, "initialize COM");
#ifndef FACENOW_DIRECTSHOW_BACKEND
        media = MFStartup(MF_VERSION); Check(media, "initialize Media Foundation");
#endif
        std::wstring command = argc > 1 ? argv[1] : L"--status";
        if (command == L"--install") Install();
        else if (command == L"--enable") Enable();
        else if (command == L"--remove") Remove();
        else if (command == L"--status") Status();
#ifdef FACENOW_DIRECTSHOW_BACKEND
        else if (command == L"--remove-elevated") RemoveInstalledDirectShow();
#else
        else if (command == L"--self-test" || command == L"--verify") Verify(command == L"--self-test", argc > 2 ? fs::path(argv[2]) : fs::path());
        // Offline integration test: instantiate only the sibling DLL, with no device registration.
        else if (command == L"--self-test-relay" && argc == 4) Verify(true, fs::path(argv[3]), argv[2]);
        else if (command == L"--self-test-relay-late-link" && argc == 4) Verify(true, fs::path(argv[3]), argv[2], true);
        else if (command == L"--self-test-relay-capture" && argc == 4) {
            auto capture = FaceNowFrames::DeviceInterfaceLink(argv[2], FaceNowFrames::CaptureCategory);
            if (_wcsicmp(capture.c_str(), argv[2]) == 0) throw Failure{MF_E_NOT_FOUND,"resolve DirectShow camera interface"};
            Verify(true, fs::path(argv[3]), capture);
        }
#endif
        else throw Failure{E_INVALIDARG,"unknown camera command"};
    } catch (const Failure& error) {
        std::cerr << "{\"error\":\"" << error.operation << "\",\"hresult\":\"0x" << std::hex << (unsigned long)error.code << "\"}\n"; result = 1;
    } catch (const std::exception& error) { std::cerr << "Camera operation failed: " << error.what() << '\n'; result = 1; }
#ifndef FACENOW_DIRECTSHOW_BACKEND
    if (SUCCEEDED(media)) MFShutdown();
#endif
    if (SUCCEEDED(com)) CoUninitialize();
    return result;
}
