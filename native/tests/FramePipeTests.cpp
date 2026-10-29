#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <wil/resource.h>
#include <wil/com.h>
#include <atomic>
#include <thread>
#include <vector>
#include <iostream>
#include <stdexcept>
#include "../CameraSource/FramePipe.h"

static void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
static bool Transfer(HANDLE pipe, void* data, DWORD size, bool writing) {
    wil::unique_handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    auto cursor = static_cast<BYTE*>(data);
    while (size) {
        OVERLAPPED operation{}; operation.hEvent = event.get(); ResetEvent(event.get());
        DWORD count = 0;
        BOOL done = writing ? WriteFile(pipe, cursor, size, &count, &operation) : ReadFile(pipe, cursor, size, &count, &operation);
        if (!done) {
            if (GetLastError() != ERROR_IO_PENDING) return false;
            if (WaitForSingleObject(event.get(), 2000) != WAIT_OBJECT_0) {
                CancelIoEx(pipe, &operation); GetOverlappedResult(pipe, &operation, &count, TRUE); return false;
            }
            if (!GetOverlappedResult(pipe, &operation, &count, FALSE)) return false;
        }
        if (!count || count > size) return false;
        cursor += count; size -= count;
    }
    return true;
}

static void Verify(bool bottomUp, bool lateAttributes, UINT sourceWidth, UINT sourceHeight) {
    static unsigned test = 0;
    std::wstring link = L"FaceNow-test-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(++test);
    auto name = FaceNowFrames::PipeName(link);
    wil::unique_hfile server{CreateNamedPipeW(name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536, 4096, 0, nullptr)};
    Check(server && server.get() != INVALID_HANDLE_VALUE, "Could not create isolated test pipe.");
    std::vector<uint32_t> source(size_t(sourceWidth) * sourceHeight);
    for (UINT y = 0; y < sourceHeight; ++y) for (UINT x = 0; x < sourceWidth; ++x)
        source[size_t(y) * sourceWidth + x] = 0xff000000 | (x % 200) | ((y % 200) << 8) | 0x400000;
    std::atomic<bool> connected = false, served = false;
    std::thread worker([&] {
        wil::unique_handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
        OVERLAPPED operation{}; operation.hEvent = event.get();
        if (!ConnectNamedPipe(server.get(), &operation)) {
            DWORD code = GetLastError();
            if (code == ERROR_IO_PENDING) {
                if (WaitForSingleObject(event.get(), 2000) != WAIT_OBJECT_0) {
                    CancelIoEx(server.get(), &operation); DWORD count = 0;
                    GetOverlappedResult(server.get(), &operation, &count, TRUE); return;
                }
                DWORD count = 0; if (!GetOverlappedResult(server.get(), &operation, &count, FALSE)) return;
            } else if (code != ERROR_PIPE_CONNECTED) return;
        }
        connected = true;
        FaceNowFrames::Request request;
        if (!Transfer(server.get(), &request, sizeof(request), false) || request.magic != FaceNowFrames::Magic) return;
        FaceNowFrames::Header header;
        header.width = sourceWidth; header.height = sourceHeight; header.stride = sourceWidth * 4;
        header.length = static_cast<DWORD>(source.size() * 4); header.active = 1;
        served = Transfer(server.get(), &header, sizeof(header), true) && Transfer(server.get(), source.data(), header.length, true);
    });
    struct Join { std::thread& value; ~Join() { if (value.joinable()) value.join(); } } join{worker};
    wil::com_ptr_nothrow<IMFAttributes> attributes;
    Check(SUCCEEDED(MFCreateAttributes(&attributes, 1)), "Could not create source attributes.");
    if (!lateAttributes) attributes->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, link.c_str());
    FramePipe frames; frames.Configure(attributes.get());
    if (lateAttributes) attributes->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, link.c_str());
    constexpr UINT width = 1920, height = 1080, pitch = width + 4;
    std::vector<uint32_t> pixels(size_t(pitch) * height + 8, 0xdeadbeef);
    auto scanline0 = pixels.data() + (bottomUp ? size_t(height - 1) * pitch : 0);
    bool drawn = frames.Draw(reinterpret_cast<BYTE*>(scanline0), pitch * height * 4,
        bottomUp ? -LONG(pitch * 4) : LONG(pitch * 4), width, height);
    worker.join();
    Check(drawn && connected && served, "A valid Windows RGB buffer did not connect and receive a frame.");
    for (UINT y = 0; y < height; ++y) {
        auto row = pixels.data() + size_t(bottomUp ? height - 1 - y : y) * pitch;
        // Source and destination share 16:9 here; verify orientation and row padding.
        UINT sourceY = UINT((uint64_t(2 * y + 1) * sourceHeight) / (2 * height));
        for (UINT x = 0; x < width; ++x) {
            UINT sourceX = UINT((uint64_t(2 * x + 1) * sourceWidth) / (2 * width));
            Check(row[x] == source[size_t(sourceY) * sourceWidth + sourceX], "Frame orientation or pixels are incorrect.");
        }
        for (UINT x = width; x < pitch; ++x) Check(row[x] == 0xdeadbeef, "Row padding was overwritten.");
    }
    for (size_t i = size_t(pitch) * height; i < pixels.size(); ++i) Check(pixels[i] == 0xdeadbeef, "Output overrun.");
    std::cout << "PASS real pipe " << sourceWidth << 'x' << sourceHeight << (bottomUp ? " bottom-up" : " top-down")
        << (lateAttributes ? " late attributes" : " initial attributes") << '\n';
}

int main() {
    HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(com)) return 1;
    int result = 0;
    try {
        Verify(false, false, 1920, 1080);
        Verify(true, false, 1920, 1080);
        Verify(true, false, 1728, 972);
        Verify(false, true, 1728, 972);
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
    CoUninitialize(); return result;
}
