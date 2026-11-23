//
//  CameraFilter.cpp
//  FaceNow
//

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
#include "../Identity.h"
#include "../CameraPlaceholder.h"

namespace {
#ifdef FACENOW_DIRECTSHOW_PROTOTYPE
constexpr GUID FilterId = {0x98eecdf2, 0xd88c, 0x4638, {0xa9, 0x35, 0xf2, 0x27, 0x17, 0x56, 0xeb, 0x6f}};
constexpr wchar_t FilterName[] = L"FaceNow DirectShow Test";
constexpr UINT DefaultWidth = 1280, DefaultHeight = 720;
constexpr uint32_t Placeholder = 0xff303030;
#else
constexpr auto FilterId = DirectShowId;
constexpr auto& FilterName = CameraName;
constexpr UINT DefaultWidth = 1920, DefaultHeight = 1080;
#endif
constexpr REFERENCE_TIME TicksPerSecond = 10'000'000;
constexpr REFERENCE_TIME FastestInterval = TicksPerSecond / 30;
constexpr REFERENCE_TIME SlowestInterval = TicksPerSecond;

DWORD BitRate(DWORD bytes, REFERENCE_TIME interval) {
    return static_cast<DWORD>(static_cast<uint64_t>(bytes) * 8 * TicksPerSecond / interval);
}

class CameraPin final : public CSourceStream, public IAMStreamConfig, public IKsPropertySet {
    std::wstring endpoint;
    UINT width = DefaultWidth, height = DefaultHeight;
    bool negotiating = false;
    std::optional<FramePipe> frames;
    FaceNowFrames::WaitingCanvas waiting;
    ULONGLONG startedAt = 0;
    REFERENCE_TIME preferredInterval = FastestInterval;
    REFERENCE_TIME connectedInterval = FastestInterval;
    bool intervalSelected = false;
    REFERENCE_TIME nextSample = 0;

    LONG Pitch() const { return static_cast<LONG>(width * 4); }
    LONG ImageBytes() const { return Pitch() * static_cast<LONG>(height); }

    HRESULT ValidateFormat(const CMediaType* type) const {
        if (type->majortype != MEDIATYPE_Video || type->subtype != MEDIASUBTYPE_RGB32 ||
            type->formattype != FORMAT_VideoInfo || type->cbFormat < sizeof(VIDEOINFOHEADER) || !type->pbFormat)
            return VFW_E_TYPE_NOT_ACCEPTED;
        const auto& format = *reinterpret_cast<const VIDEOINFOHEADER*>(type->pbFormat);
        const auto& bitmap = format.bmiHeader;
        REFERENCE_TIME interval = format.AvgTimePerFrame;
        return bitmap.biWidth == static_cast<LONG>(width) && bitmap.biHeight == static_cast<LONG>(height) && bitmap.biPlanes == 1 &&
            bitmap.biBitCount == 32 && bitmap.biCompression == BI_RGB &&
            (interval == 0 || (interval >= FastestInterval && interval <= SlowestInterval)) ? S_OK : VFW_E_TYPE_NOT_ACCEPTED;
    }

    HRESULT RefreshFormat() {
#ifndef FACENOW_DIRECTSHOW_PROTOTYPE
        // Connected pins keep the format their downstream buffers were allocated for.
        if (IsConnected() || negotiating) return S_OK;
        UINT nextWidth = DefaultWidth, nextHeight = DefaultHeight;
        try {
            FramePipe configuration;
            configuration.ConfigureEndpoint(endpoint);
            bool publisherMissing = false;
            if (!configuration.TryReadFormat(nextWidth, nextHeight, &publisherMissing) && !publisherMissing)
                return S_OK;
        } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
        if (width != nextWidth || height != nextHeight) {
            width = nextWidth;
            height = nextHeight;
            IncrementTypeVersion();
        }
#endif
        return S_OK;
    }

public:
    CameraPin(CSource* filter, HRESULT* result) : CSourceStream(FilterName, result, filter, L"Capture") {
        if (FAILED(*result)) return;
        DWORD session = 0;
        if (!ProcessIdToSessionId(GetCurrentProcessId(), &session)) {
            *result = HRESULT_FROM_WIN32(GetLastError());
            return;
        }
#ifdef FACENOW_DIRECTSHOW_PROTOTYPE
        endpoint = L"FaceNow.DirectShow.Prototype." + std::to_wstring(session);
#else
        endpoint = DirectShowEndpoint(session);
#endif
    }

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
        format->AvgTimePerFrame = IsConnected() ? connectedInterval : preferredInterval;
        format->dwBitRate = BitRate(ImageBytes(), format->AvgTimePerFrame);
        auto& bitmap = format->bmiHeader;
        bitmap.biSize = sizeof(BITMAPINFOHEADER);
        bitmap.biWidth = static_cast<LONG>(width);
        bitmap.biHeight = static_cast<LONG>(height);
        bitmap.biPlanes = 1;
        bitmap.biBitCount = 32;
        bitmap.biCompression = BI_RGB;
        bitmap.biSizeImage = ImageBytes();
        type->SetType(&MEDIATYPE_Video);
        type->SetSubtype(&MEDIASUBTYPE_RGB32);
        type->SetFormatType(&FORMAT_VideoInfo);
        type->SetSampleSize(ImageBytes());
        return S_OK;
    }

    HRESULT CheckMediaType(const CMediaType* type) override {
        CAutoLock lock(m_pLock);
        HRESULT result = ValidateFormat(type);
        if (FAILED(result)) return result;
        auto interval = reinterpret_cast<const VIDEOINFOHEADER*>(type->pbFormat)->AvgTimePerFrame;
        return intervalSelected && interval && interval != preferredInterval ? VFW_E_TYPE_NOT_ACCEPTED : S_OK;
    }

    HRESULT SetMediaType(const CMediaType* type) override {
        HRESULT result = CSourceStream::SetMediaType(type);
        if (FAILED(result)) return result;
#ifndef FACENOW_DIRECTSHOW_PROTOTYPE
        result = waiting.Configure(width, height);
        if (FAILED(result)) return result;
#endif
        auto interval = reinterpret_cast<const VIDEOINFOHEADER*>(type->pbFormat)->AvgTimePerFrame;
        connectedInterval = interval ? interval : preferredInterval;
        return S_OK;
    }

    STDMETHODIMP Connect(IPin* input, const AM_MEDIA_TYPE* type) override {
        CAutoLock lock(m_pLock);
        HRESULT result = RefreshFormat();
        if (FAILED(result)) return result;
        auto restoreNegotiation = wil::scope_exit([&, previous = negotiating] { negotiating = previous; });
        negotiating = true;
        return CSourceStream::Connect(input, type);
    }

    STDMETHODIMP EnumMediaTypes(IEnumMediaTypes** types) override {
        CAutoLock lock(m_pLock);
        HRESULT result = RefreshFormat();
        return FAILED(result) ? result : CSourceStream::EnumMediaTypes(types);
    }

    HRESULT DecideBufferSize(IMemAllocator* allocator, ALLOCATOR_PROPERTIES* requested) override {
        requested->cBuffers = std::max<LONG>(requested->cBuffers, 1);
        requested->cbBuffer = std::max<LONG>(requested->cbBuffer, ImageBytes());
        ALLOCATOR_PROPERTIES actual{};
        HRESULT result = allocator->SetProperties(requested, &actual);
        if (FAILED(result)) return result;
        return actual.cbBuffer >= ImageBytes() && actual.cBuffers >= requested->cBuffers ? S_OK : E_FAIL;
    }

    HRESULT OnThreadCreate() override {
        try {
            frames.emplace().ConfigureEndpoint(endpoint);
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
        if (sample->GetSize() < ImageBytes()) return E_FAIL;

        const auto elapsed = static_cast<REFERENCE_TIME>(GetTickCount64() - startedAt) * 10'000;
        if (elapsed < nextSample) Sleep(static_cast<DWORD>((nextSample - elapsed + 9'999) / 10'000));
        try {
            // Positive DIB height stores the bottom row first. FramePipe reads top-down BGRA.
            if (!frames->Draw(data + (height - 1) * Pitch(), ImageBytes(), -Pitch(), width, height)) {
#ifdef FACENOW_DIRECTSHOW_PROTOTYPE
                std::fill_n(reinterpret_cast<uint32_t*>(data), ImageBytes() / 4, Placeholder);
#else
                waiting.Draw(data + (height - 1) * Pitch(), -Pitch());
#endif
            }
        } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }

        auto start = std::max(nextSample, elapsed);
        nextSample = start + connectedInterval;
        sample->SetTime(&start, &nextSample);
        sample->SetSyncPoint(TRUE);
        return sample->SetActualDataLength(ImageBytes());
    }

    STDMETHODIMP SetFormat(AM_MEDIA_TYPE* type) override {
        if (!type) return E_POINTER;
        if (type->cbFormat && !type->pbFormat) return E_INVALIDARG;
        CAutoLock lock(m_pLock);
        HRESULT result = RefreshFormat();
        if (FAILED(result)) return result;
        const CMediaType requested(*type, &result);
        if (FAILED(result)) return result;
        result = ValidateFormat(&requested);
        if (FAILED(result)) return result;
        auto interval = reinterpret_cast<const VIDEOINFOHEADER*>(requested.pbFormat)->AvgTimePerFrame;
        if (!interval) interval = FastestInterval;
        if (IsConnected()) return interval == connectedInterval ? S_OK : VFW_E_ALREADY_CONNECTED;
        intervalSelected = true;
        if (interval != preferredInterval) {
            preferredInterval = interval;
            IncrementTypeVersion();
        }
        return S_OK;
    }

    STDMETHODIMP GetFormat(AM_MEDIA_TYPE** type) override {
        if (!type) return E_POINTER;
        *type = nullptr;
        CAutoLock lock(m_pLock);
        HRESULT result = RefreshFormat();
        if (FAILED(result)) return result;
        CMediaType format;
        result = GetMediaType(&format);
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
        HRESULT result = GetFormat(type);
        if (FAILED(result)) return result;
        const auto& format = *reinterpret_cast<const VIDEOINFOHEADER*>((*type)->pbFormat);
        VIDEO_STREAM_CONFIG_CAPS caps{};
        caps.guid = FORMAT_VideoInfo;
        caps.InputSize = caps.MinCroppingSize = caps.MaxCroppingSize = caps.MinOutputSize = caps.MaxOutputSize =
            {format.bmiHeader.biWidth, format.bmiHeader.biHeight};
        caps.CropGranularityX = caps.CropGranularityY = caps.OutputGranularityX = caps.OutputGranularityY = 1;
        caps.MinFrameInterval = FastestInterval;
        caps.MaxFrameInterval = SlowestInterval;
        caps.MinBitsPerSecond = static_cast<LONG>(BitRate(format.bmiHeader.biSizeImage, SlowestInterval));
        caps.MaxBitsPerSecond = static_cast<LONG>(BitRate(format.bmiHeader.biSizeImage, FastestInterval));
        memcpy(capabilities, &caps, sizeof(caps));
        return S_OK;
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
    CameraFilter(IUnknown* outer, HRESULT* result) : CSource(FilterName, outer, FilterId, result) {
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
    if (!install) return mapper->UnregisterFilter(&CLSID_VideoInputDeviceCategory, nullptr, FilterId);

    REGPINTYPES type{&MEDIATYPE_Video, &MEDIASUBTYPE_RGB32};
    REGFILTERPINS2 pin{REG_PINFLAG_B_OUTPUT, 1, 1, &type, 0, nullptr, &PIN_CATEGORY_CAPTURE};
    REGFILTER2 filter{};
    filter.dwVersion = 2;
    filter.dwMerit = MERIT_DO_NOT_USE;
    filter.cPins2 = 1;
    filter.rgPins2 = &pin;
    return mapper->RegisterFilter(FilterId, FilterName, nullptr, &CLSID_VideoInputDeviceCategory, nullptr, &filter);
}
}

CFactoryTemplate g_Templates[] = {{FilterName, &FilterId, CameraFilter::Create, nullptr, nullptr}};
int g_cTemplates = ARRAYSIZE(g_Templates);

extern "C" BOOL WINAPI DllEntryPoint(HINSTANCE, ULONG, LPVOID);
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    return DllEntryPoint(module, reason, reserved);
}

STDAPI DllRegisterServer() {
    HRESULT result = AMovieDllRegisterServer2(TRUE);
    if (FAILED(result)) return result;
    const HRESULT apartment = CoInitialize(nullptr);
    result = apartment;
    if (SUCCEEDED(apartment) || apartment == RPC_E_CHANGED_MODE) {
        result = RegisterCaptureCategory(true);
        if (SUCCEEDED(apartment)) CoUninitialize();
    }
    if (FAILED(result)) AMovieDllRegisterServer2(FALSE);
    return result;
}

STDAPI DllUnregisterServer() {
    const HRESULT apartment = CoInitialize(nullptr);
    HRESULT result = apartment;
    if (SUCCEEDED(apartment) || apartment == RPC_E_CHANGED_MODE) {
        result = RegisterCaptureCategory(false);
        if (SUCCEEDED(apartment)) CoUninitialize();
    }
    if (FAILED(result) && result != HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND) &&
        result != HRESULT_FROM_WIN32(ERROR_PATH_NOT_FOUND) && result != VFW_E_NOT_FOUND) return result;
    return AMovieDllRegisterServer2(FALSE);
}
