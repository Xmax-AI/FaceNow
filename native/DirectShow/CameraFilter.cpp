#include <streams.h>
#include <ks.h>
#include <ksmedia.h>
#include <mfapi.h>
#include <mfidl.h>
#include <wil/resource.h>
#include <wil/com.h>
#include <wrl/client.h>
#include <new>
#include <optional>
#include "../CameraSource/FramePipe.h"

namespace {
constexpr GUID CameraId = {0x98eecdf2, 0xd88c, 0x4638, {0xa9, 0x35, 0xf2, 0x27, 0x17, 0x56, 0xeb, 0x6f}};
constexpr wchar_t CameraName[] = L"FaceNow DirectShow Test";
constexpr LONG Width = 1280;
constexpr LONG Height = 720;
constexpr LONG Pitch = Width * 4;
constexpr LONG ImageBytes = Pitch * Height;
constexpr REFERENCE_TIME FrameDuration = 10'000'000 / 30;

class CameraPin final : public CSourceStream, public IAMStreamConfig, public IKsPropertySet {
    std::optional<FramePipe> frames;
    ULONGLONG startedAt = 0;
    REFERENCE_TIME nextSample = 0;

public:
    CameraPin(CSource* filter, HRESULT* result) : CSourceStream(CameraName, result, filter, L"Capture") {}

    DECLARE_IUNKNOWN;
    STDMETHODIMP NonDelegatingQueryInterface(REFIID iid, void** object) override {
        if (iid == IID_IAMStreamConfig) return GetInterface(static_cast<IAMStreamConfig*>(this), object);
        if (iid == IID_IKsPropertySet) return GetInterface(static_cast<IKsPropertySet*>(this), object);
        return CSourceStream::NonDelegatingQueryInterface(iid, object);
    }

    HRESULT GetMediaType(CMediaType* type) override {
        *type = CMediaType{};
        auto format = reinterpret_cast<VIDEOINFOHEADER*>(type->AllocFormatBuffer(sizeof(VIDEOINFOHEADER)));
        if (!format) return E_OUTOFMEMORY;
        *format = {};
        format->AvgTimePerFrame = FrameDuration;
        format->dwBitRate = ImageBytes * 8 * 30;
        auto& bitmap = format->bmiHeader;
        bitmap.biSize = sizeof(BITMAPINFOHEADER);
        bitmap.biWidth = Width;
        bitmap.biHeight = Height;
        bitmap.biPlanes = 1;
        bitmap.biBitCount = 32;
        bitmap.biCompression = BI_RGB;
        bitmap.biSizeImage = ImageBytes;
        type->SetType(&MEDIATYPE_Video);
        type->SetSubtype(&MEDIASUBTYPE_RGB32);
        type->SetFormatType(&FORMAT_VideoInfo);
        type->SetSampleSize(ImageBytes);
        return S_OK;
    }

    HRESULT CheckMediaType(const CMediaType* type) override {
        if (type->majortype != MEDIATYPE_Video || type->subtype != MEDIASUBTYPE_RGB32 ||
            type->formattype != FORMAT_VideoInfo || type->cbFormat < sizeof(VIDEOINFOHEADER) || !type->pbFormat)
            return VFW_E_TYPE_NOT_ACCEPTED;
        const auto& format = *reinterpret_cast<const VIDEOINFOHEADER*>(type->pbFormat);
        const auto& bitmap = format.bmiHeader;
        return bitmap.biWidth == Width && bitmap.biHeight == Height && bitmap.biPlanes == 1 &&
            bitmap.biBitCount == 32 && bitmap.biCompression == BI_RGB &&
            (format.AvgTimePerFrame == 0 || format.AvgTimePerFrame == FrameDuration) ? S_OK : VFW_E_TYPE_NOT_ACCEPTED;
    }

    HRESULT DecideBufferSize(IMemAllocator* allocator, ALLOCATOR_PROPERTIES* requested) override {
        requested->cBuffers = std::max<LONG>(requested->cBuffers, 1);
        requested->cbBuffer = std::max<LONG>(requested->cbBuffer, ImageBytes);
        ALLOCATOR_PROPERTIES actual{};
        HRESULT result = allocator->SetProperties(requested, &actual);
        if (FAILED(result)) return result;
        return actual.cbBuffer >= ImageBytes && actual.cBuffers >= requested->cBuffers ? S_OK : E_FAIL;
    }

    HRESULT OnThreadCreate() override {
        DWORD session = 0;
        if (!ProcessIdToSessionId(GetCurrentProcessId(), &session)) return HRESULT_FROM_WIN32(GetLastError());
        try {
            frames.emplace().ConfigureEndpoint(L"FaceNow.DirectShow.Prototype." + std::to_wstring(session));
        } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
        startedAt = GetTickCount64();
        nextSample = 0;
        return S_OK;
    }

    HRESULT OnThreadDestroy() override {
        frames.reset();
        return S_OK;
    }

    HRESULT FillBuffer(IMediaSample* sample) override {
        BYTE* data = nullptr;
        HRESULT result = sample->GetPointer(&data);
        if (FAILED(result)) return result;
        if (sample->GetSize() < ImageBytes) return E_FAIL;

        const auto elapsed = static_cast<REFERENCE_TIME>(GetTickCount64() - startedAt) * 10'000;
        if (elapsed < nextSample) Sleep(static_cast<DWORD>((nextSample - elapsed + 9'999) / 10'000));
        try {
            // Positive DIB height stores the bottom row first. FramePipe reads top-down BGRA.
            if (!frames->Draw(data + (Height - 1) * Pitch, ImageBytes, -Pitch, Width, Height))
                std::fill_n(reinterpret_cast<uint32_t*>(data), ImageBytes / 4, 0xff303030u);
        } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }

        auto start = std::max(nextSample, elapsed);
        nextSample = start + FrameDuration;
        sample->SetTime(&start, &nextSample);
        sample->SetSyncPoint(TRUE);
        return sample->SetActualDataLength(ImageBytes);
    }

    STDMETHODIMP SetFormat(AM_MEDIA_TYPE* type) override {
        if (!type) return E_POINTER;
        if (type->cbFormat && !type->pbFormat) return E_INVALIDARG;
        HRESULT result = S_OK;
        const CMediaType requested(*type, &result);
        return FAILED(result) ? result : CheckMediaType(&requested);
    }

    STDMETHODIMP GetFormat(AM_MEDIA_TYPE** type) override {
        if (!type) return E_POINTER;
        *type = nullptr;
        CMediaType format;
        HRESULT result = GetMediaType(&format);
        if (FAILED(result)) return result;
        *type = CreateMediaType(&format);
        return *type ? S_OK : E_OUTOFMEMORY;
    }

    STDMETHODIMP GetNumberOfCapabilities(int* count, int* size) override {
        if (!count || !size) return E_POINTER;
        *count = 1;
        *size = sizeof(VIDEO_STREAM_CONFIG_CAPS);
        return S_OK;
    }

    STDMETHODIMP GetStreamCaps(int index, AM_MEDIA_TYPE** type, BYTE* capabilities) override {
        if (!type || !capabilities) return E_POINTER;
        *type = nullptr;
        if (index < 0) return E_INVALIDARG;
        if (index != 0) return S_FALSE;
        VIDEO_STREAM_CONFIG_CAPS caps{};
        caps.guid = FORMAT_VideoInfo;
        caps.InputSize = caps.MinCroppingSize = caps.MaxCroppingSize = caps.MinOutputSize = caps.MaxOutputSize = {Width, Height};
        caps.CropGranularityX = caps.CropGranularityY = caps.OutputGranularityX = caps.OutputGranularityY = 1;
        caps.MinFrameInterval = caps.MaxFrameInterval = FrameDuration;
        caps.MinBitsPerSecond = caps.MaxBitsPerSecond = ImageBytes * 8 * 30;
        memcpy(capabilities, &caps, sizeof(caps));
        return GetFormat(type);
    }

    STDMETHODIMP Set(REFGUID, DWORD, void*, DWORD, void*, DWORD) override { return E_NOTIMPL; }

    STDMETHODIMP Get(REFGUID set, DWORD property, void*, DWORD, void* data, DWORD size, DWORD* returned) override {
        if (set != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
        if (property != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
        if (!data && !returned) return E_POINTER;
        if (returned) *returned = sizeof(GUID);
        if (!data) return S_OK;
        if (size < sizeof(GUID)) return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
        memcpy(data, &PIN_CATEGORY_CAPTURE, sizeof(GUID));
        return S_OK;
    }

    STDMETHODIMP QuerySupported(REFGUID set, DWORD property, DWORD* support) override {
        if (set != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
        if (property != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
        if (!support) return E_POINTER;
        *support = KSPROPERTY_SUPPORT_GET;
        return S_OK;
    }
};

class CameraFilter final : public CSource {
public:
    CameraFilter(IUnknown* outer, HRESULT* result) : CSource(CameraName, outer, CameraId, result) {
        if (SUCCEEDED(*result)) new CameraPin(this, result); // CSource owns its pins.
    }

    static CUnknown* WINAPI Create(IUnknown* outer, HRESULT* result) {
        try { return new CameraFilter(outer, result); }
        catch (const std::bad_alloc&) { *result = E_OUTOFMEMORY; return nullptr; }
    }
};

HRESULT RegisterCaptureCategory(bool install) {
    Microsoft::WRL::ComPtr<IFilterMapper2> mapper;
    HRESULT result = CoCreateInstance(CLSID_FilterMapper2, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&mapper));
    if (FAILED(result)) return result;
    if (!install) return mapper->UnregisterFilter(&CLSID_VideoInputDeviceCategory, nullptr, CameraId);

    REGPINTYPES type{&MEDIATYPE_Video, &MEDIASUBTYPE_RGB32};
    REGFILTERPINS2 pin{REG_PINFLAG_B_OUTPUT, 1, 1, &type, 0, nullptr, &PIN_CATEGORY_CAPTURE};
    REGFILTER2 filter{};
    filter.dwVersion = 2;
    filter.dwMerit = MERIT_DO_NOT_USE;
    filter.cPins2 = 1;
    filter.rgPins2 = &pin;
    return mapper->RegisterFilter(CameraId, CameraName, nullptr, &CLSID_VideoInputDeviceCategory, nullptr, &filter);
}
}

CFactoryTemplate g_Templates[] = {{CameraName, &CameraId, CameraFilter::Create, nullptr, nullptr}};
int g_cTemplates = ARRAYSIZE(g_Templates);

extern "C" BOOL WINAPI DllEntryPoint(HINSTANCE, ULONG, LPVOID);
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    return DllEntryPoint(module, reason, reserved);
}

STDAPI DllRegisterServer() {
    HRESULT result = AMovieDllRegisterServer2(TRUE);
    if (FAILED(result)) return result;
    result = CoInitialize(nullptr);
    if (SUCCEEDED(result)) {
        result = RegisterCaptureCategory(true);
        CoUninitialize();
    }
    if (FAILED(result)) AMovieDllRegisterServer2(FALSE);
    return result;
}

STDAPI DllUnregisterServer() {
    HRESULT result = CoInitialize(nullptr);
    if (SUCCEEDED(result)) {
        result = RegisterCaptureCategory(false);
        CoUninitialize();
    }
    HRESULT removed = AMovieDllRegisterServer2(FALSE);
    return FAILED(result) ? result : removed;
}
