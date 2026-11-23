//
//  CameraPlaceholder.h
//  FaceNow
//

#pragma once
#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>
#include <utility>
#include <vector>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace FaceNowFrames {

// Decode and resize the embedded artwork once per negotiated format, never per frame.
class WaitingCanvas final {
    UINT width = 0, height = 0, artworkWidth = 0, artworkHeight = 0;
    std::vector<uint32_t> artwork;

public:
    HRESULT Configure(UINT canvasWidth, UINT canvasHeight) try {
        if (width == canvasWidth && height == canvasHeight && !artwork.empty()) return S_OK;
        if (!canvasWidth || !canvasHeight || canvasWidth > 8192 || canvasHeight > 8192) return E_INVALIDARG;
        struct Apartment {
            HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            ~Apartment() { if (SUCCEEDED(result)) CoUninitialize(); }
        } apartment;
        if (FAILED(apartment.result) && apartment.result != RPC_E_CHANGED_MODE) return apartment.result;

        const auto module = reinterpret_cast<HMODULE>(&__ImageBase);
        const auto resource = FindResourceW(module, MAKEINTRESOURCEW(201), RT_RCDATA);
        if (!resource) return HRESULT_FROM_WIN32(ERROR_RESOURCE_DATA_NOT_FOUND);
        const auto bytes = static_cast<BYTE*>(LockResource(LoadResource(module, resource)));
        const auto length = SizeofResource(module, resource);
        if (!bytes || !length) return HRESULT_FROM_WIN32(ERROR_RESOURCE_DATA_NOT_FOUND);

        using Microsoft::WRL::ComPtr;
        ComPtr<IWICImagingFactory> factory;
        HRESULT result = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
        if (FAILED(result)) return result;
        ComPtr<IWICStream> stream;
        if (FAILED(result = factory->CreateStream(&stream))) return result;
        if (FAILED(result = stream->InitializeFromMemory(bytes, length))) return result;
        ComPtr<IWICBitmapDecoder> decoder;
        if (FAILED(result = factory->CreateDecoderFromStream(stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder))) return result;
        ComPtr<IWICBitmapFrameDecode> image;
        if (FAILED(result = decoder->GetFrame(0, &image))) return result;
        UINT sourceWidth = 0, sourceHeight = 0;
        if (FAILED(result = image->GetSize(&sourceWidth, &sourceHeight))) return result;
        if (!sourceWidth || !sourceHeight) return E_INVALIDARG;

        const double edge = std::min(canvasWidth, canvasHeight) * 0.28;
        const double scale = edge / std::max(sourceWidth, sourceHeight);
        const UINT scaledWidth = std::max(1u, static_cast<UINT>(std::lround(sourceWidth * scale)));
        const UINT scaledHeight = std::max(1u, static_cast<UINT>(std::lround(sourceHeight * scale)));
        ComPtr<IWICBitmapScaler> scaler;
        if (FAILED(result = factory->CreateBitmapScaler(&scaler))) return result;
        if (FAILED(result = scaler->Initialize(image.Get(), scaledWidth, scaledHeight, WICBitmapInterpolationModeFant))) return result;
        ComPtr<IWICFormatConverter> converter;
        if (FAILED(result = factory->CreateFormatConverter(&converter))) return result;
        if (FAILED(result = converter->Initialize(scaler.Get(), GUID_WICPixelFormat32bppBGRA,
                WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) return result;
        std::vector<uint32_t> pixels(size_t(scaledWidth) * scaledHeight);
        if (FAILED(result = converter->CopyPixels(nullptr, scaledWidth * 4,
                static_cast<UINT>(pixels.size() * 4), reinterpret_cast<BYTE*>(pixels.data())))) return result;
        artwork = std::move(pixels);
        width = canvasWidth;
        height = canvasHeight;
        artworkWidth = scaledWidth;
        artworkHeight = scaledHeight;
        return S_OK;
    } catch (const std::bad_alloc&) {
        return E_OUTOFMEMORY;
    }

    // scanline0 is the displayed top row, including for bottom-up DirectShow buffers.
    void Draw(BYTE* scanline0, LONG pitch) const {
        for (UINT y = 0; y < height; ++y)
            std::fill_n(reinterpret_cast<uint32_t*>(scanline0 + int64_t(y) * pitch), width, 0xffffffff);
        const UINT left = (width - artworkWidth) / 2, top = (height - artworkHeight) / 2;
        for (UINT y = 0; y < artworkHeight; ++y)
            std::memcpy(scanline0 + int64_t(top + y) * pitch + size_t(left) * 4,
                artwork.data() + size_t(y) * artworkWidth, size_t(artworkWidth) * 4);
    }
};

}
