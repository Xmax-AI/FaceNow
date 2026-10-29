#pragma once
#include "../FrameProtocol.h"
#include "CenterFill.h"
#include "SourceDiagnostics.h"

// One bounded request/response per sample. Failure immediately selects the placeholder;
// no stale image is kept after disconnect, timeout or a publisher's inactive response.
class FramePipe {
    wil::unique_hfile pipe;
    wil::unique_handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    std::wstring name;
    std::vector<BYTE> pixels;
    ULONGLONG retryAt = 0;
    FaceNowFrames::Header header{};
    wil::com_ptr_nothrow<IMFAttributes> sourceAttributes;
    const wchar_t* lastStage = L"";
    DWORD lastCode = 0;
    bool describedBuffer = false;
    LONG outputPitch = 0;
    UINT outputWidth = 0, outputHeight = 0;

    void Record(const wchar_t* stage, DWORD code) {
        if (wcscmp(lastStage, stage) == 0 && lastCode == code) return;
        lastStage = stage; lastCode = code;
        SourceDiagnostic(stage, code, outputPitch, outputWidth, outputHeight, name);
    }
    void ResolveName() {
        wil::unique_cotaskmem_string link;
        UINT32 characters = 0;
        HRESULT result = sourceAttributes ? sourceAttributes->GetAllocatedString(
            MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &link, &characters) : E_POINTER;
        if (FAILED(result)) { Record(L"name-missing", static_cast<DWORD>(result)); return; }
        auto next = FaceNowFrames::PipeName(link.get());
        if (next.empty()) { Record(L"name-hash", GetLastError()); return; }
        if (next != name) { pipe.reset(); name = std::move(next); retryAt = 0; }
        Record(L"name-ready", ERROR_SUCCESS);
    }

    bool Transfer(void* data, DWORD size, bool write, ULONGLONG deadline) {
        auto cursor = static_cast<BYTE*>(data);
        while (size) {
            OVERLAPPED operation{}; operation.hEvent = event.get(); ResetEvent(event.get());
            DWORD transferred = 0;
            BOOL done = write ? WriteFile(pipe.get(), cursor, size, &transferred, &operation)
                              : ReadFile(pipe.get(), cursor, size, &transferred, &operation);
            if (!done) {
                if (GetLastError() != ERROR_IO_PENDING) { Record(write ? L"request-write" : L"frame-read", GetLastError()); return false; }
                ULONGLONG now = GetTickCount64();
                DWORD wait = now < deadline ? static_cast<DWORD>(deadline - now) : 0;
                if (WaitForSingleObject(event.get(), wait) != WAIT_OBJECT_0) {
                    CancelIoEx(pipe.get(), &operation);
                    // OVERLAPPED and destination must outlive completion, including cancellation.
                    GetOverlappedResult(pipe.get(), &operation, &transferred, TRUE);
                    Record(L"transfer-timeout", WAIT_TIMEOUT);
                    return false;
                }
                if (!GetOverlappedResult(pipe.get(), &operation, &transferred, FALSE)) { Record(L"transfer-result", GetLastError()); return false; }
            }
            if (!transferred || transferred > size) return false;
            cursor += transferred; size -= transferred;
        }
        return true;
    }
public:
    void Configure(IMFAttributes* attributes) {
        sourceAttributes = attributes;
        ResolveName();
    }
    bool Draw(BYTE* output, DWORD length, LONG pitch, UINT width, UINT height) {
        outputPitch = pitch; outputWidth = width; outputHeight = height;
        if (!describedBuffer) { SourceDiagnostic(L"buffer", ERROR_SUCCESS, pitch, width, height, name); describedBuffer = true; }
        // The pipeline can populate source attributes after activation/start.
        if (name.empty()) ResolveName();
        if (name.empty() || !event) return false;
        if (!output || !FaceNowFrames::BgraLayoutFits(width, height, pitch, length)) { Record(L"buffer-invalid", ERROR_INVALID_PARAMETER); return false; }
        auto fail = [&] { pipe.reset(); retryAt = GetTickCount64() + 250; return false; };
        if (!pipe) {
            if (GetTickCount64() < retryAt) return false;
            // Request only data rights; GENERIC_WRITE also asks for pipe-instance creation.
            pipe.reset(CreateFileW(name.c_str(), FILE_READ_DATA | FILE_WRITE_DATA | SYNCHRONIZE, 0, nullptr, OPEN_EXISTING,
                FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr));
            if (!pipe || pipe.get() == INVALID_HANDLE_VALUE) { Record(L"connect", GetLastError()); return fail(); }
            Record(L"connected", ERROR_SUCCESS);
        }
        auto deadline = GetTickCount64() + 100;
        FaceNowFrames::Request request;
        if (!Transfer(&request, sizeof(request), true, deadline) ||
            !Transfer(&header, sizeof(header), false, deadline)) return fail();
        if (header.magic != FaceNowFrames::Magic || header.version != FaceNowFrames::Version || header.reserved || header.active > 1) return fail();
        if (!header.active) { if (header.length) return fail(); Record(L"waiting-for-frame", ERROR_NOT_READY); return false; }
        if (header.width < 1 || header.width > 4096 || header.height < 1 || header.height > 2160 ||
            header.stride < header.width * 4 || header.stride > 32768 || header.length > FaceNowFrames::MaxBytes ||
            header.length != static_cast<uint64_t>(header.stride) * header.height) return fail();
        pixels.resize(header.length);
        if (!Transfer(pixels.data(), header.length, false, deadline)) return fail();
        FaceNowFrames::CenterFill(pixels.data(), header.width, header.height, header.stride,
            output, width, height, pitch);
        Record(L"frame-drawn", ERROR_SUCCESS);
        return true;
    }
};
