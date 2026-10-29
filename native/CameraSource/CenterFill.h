#pragma once
#include <cstdint>
#include <cstring>

namespace FaceNowFrames {
inline bool BgraLayoutFits(uint32_t width, uint32_t height, int64_t pitch, uint64_t length) {
    if (!width || !height || pitch < INT32_MIN || pitch > INT32_MAX) return false;
    const auto rowBytes = uint64_t(width) * 4;
    const auto stride = uint64_t(pitch < 0 ? -pitch : pitch);
    return stride >= rowBytes && stride * (height - 1) + rowBytes <= length;
}
// Validated BGRA buffers. Sample pixel centers with one scale for both axes,
// cropping the excess equally from opposite edges instead of adding black bars.
inline void CenterFill(const uint8_t* input, uint32_t sourceWidth, uint32_t sourceHeight, uint32_t sourceStride,
    uint8_t* output, uint32_t width, uint32_t height, int64_t pitch) {
    if (sourceWidth == width && sourceHeight == height) {
        for (uint32_t y = 0; y < height; ++y)
            std::memcpy(output + int64_t(y) * pitch, input + uint64_t(y) * sourceStride, uint64_t(width) * 4);
        return;
    }
    const bool wider = uint64_t(sourceWidth) * height > uint64_t(sourceHeight) * width;
    const uint64_t numerator = wider ? sourceHeight : sourceWidth;
    const uint64_t denominator = wider ? height : width;
    const uint64_t offsetX = uint64_t(sourceWidth) * denominator - uint64_t(width) * numerator;
    const uint64_t offsetY = uint64_t(sourceHeight) * denominator - uint64_t(height) * numerator;
    for (uint32_t y = 0; y < height; ++y) {
        const auto sourceY = (offsetY + (2ull * y + 1) * numerator) / (2 * denominator);
        const auto source = reinterpret_cast<const uint32_t*>(input + sourceY * sourceStride);
        auto destination = reinterpret_cast<uint32_t*>(output + int64_t(y) * pitch);
        for (uint32_t x = 0; x < width; ++x) {
            const auto sourceX = (offsetX + (2ull * x + 1) * numerator) / (2 * denominator);
            destination[x] = source[sourceX] | 0xff000000;
        }
    }
}
}
