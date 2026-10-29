#include "../CameraSource/CenterFill.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>

static void Verify(uint32_t sourceWidth, uint32_t sourceHeight, uint32_t width, uint32_t height, bool bottomUp = false) {
    // Coordinate-coded pixels reveal wrong crop, mirroring, row padding or distortion.
    const uint32_t sourceStride = sourceWidth + 4, pitch = width + 6;
    std::vector<uint32_t> source(sourceStride * sourceHeight, 0xdeadbeef);
    std::vector<uint32_t> output(pitch * height + 8, 0xdeadbeef);
    for (uint32_t y = 0; y < sourceHeight; ++y)
        for (uint32_t x = 0; x < sourceWidth; ++x) source[y * sourceStride + x] = 0xff000000 | x | (y << 12);
    auto scanline0 = output.data() + (bottomUp ? size_t(height - 1) * pitch : 0);
    FaceNowFrames::CenterFill(reinterpret_cast<const uint8_t*>(source.data()), sourceWidth, sourceHeight, sourceStride * 4,
        reinterpret_cast<uint8_t*>(scanline0), width, height, bottomUp ? -int64_t(pitch * 4) : int64_t(pitch * 4));

    // Independent floating-point reference: a uniformly scaled image centered in the viewport.
    const double scale = std::max(double(width) / sourceWidth, double(height) / sourceHeight);
    const double left = (sourceWidth * scale - width) / 2, top = (sourceHeight * scale - height) / 2;
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const auto sx = uint32_t(std::floor((left + x + .5) / scale + 1e-9));
            const auto sy = uint32_t(std::floor((top + y + .5) / scale + 1e-9));
            const auto expected = 0xff000000 | sx | (sy << 12);
            if (output[size_t(bottomUp ? height - 1 - y : y) * pitch + x] != expected) throw std::runtime_error("Incorrect fill/crop pixel.");
        }
        for (uint32_t x = width; x < pitch; ++x)
            if (output[y * pitch + x] != 0xdeadbeef) throw std::runtime_error("Output row padding overwritten.");
    }
    for (size_t i = size_t(pitch) * height; i < output.size(); ++i)
        if (output[i] != 0xdeadbeef) throw std::runtime_error("Output buffer overrun.");
    std::cout << "PASS center fill " << sourceWidth << 'x' << sourceHeight << " -> " << width << 'x' << height << (bottomUp ? " bottom-up" : " top-down") << '\n';
}

int main() {
    try {
        Verify(1920, 1080, 1920, 1080); // direct copy, no resampling
        Verify(1680, 896, 1280, 720); // actual AI stream ratio
        Verify(1920, 1024, 1280, 720);
        Verify(160, 80, 1280, 720);   // wider: crop left/right
        Verify(80, 160, 1280, 720);   // portrait: crop top/bottom
        Verify(160, 90, 1280, 720);  // matching ratio, upscale
        Verify(1280, 720, 1280, 720);
        Verify(321, 179, 127, 73);   // fractional, odd dimensions
        Verify(179, 321, 127, 73);
        Verify(1, 1, 1280, 720);
        Verify(1, 160, 1280, 720);
        Verify(160, 1, 1280, 720);
        Verify(4096, 2160, 1280, 720);
        Verify(1920, 1080, 1920, 1080, true);
        Verify(1728, 972, 1920, 1080, true);
        Verify(160, 80, 1280, 720, true);
        Verify(80, 160, 1280, 720, true);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
