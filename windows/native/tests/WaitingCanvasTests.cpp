#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "../CameraPlaceholder.h"
#include <iostream>
#include <stdexcept>

static void Check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}

static void Verify(FaceNowFrames::WaitingCanvas& canvas, UINT width, UINT height, bool bottomUp) {
    Check(SUCCEEDED(canvas.Configure(width, height)), "Could not decode embedded FaceNow camera artwork.");
    const UINT pitch = width + 5;
    constexpr uint32_t guard = 0xdeadbeef;
    std::vector<uint32_t> pixels(size_t(pitch) * height + 8, guard);
    auto first = reinterpret_cast<BYTE*>(pixels.data() + (bottomUp ? size_t(height - 1) * pitch : 0));
    canvas.Draw(first, bottomUp ? -LONG(pitch * 4) : LONG(pitch * 4));
    UINT minX = width, minY = height, maxX = 0, maxY = 0, count = 0;
    const double side = std::min(width, height) * 0.28;
    for (UINT y = 0; y < height; ++y) {
        const auto row = pixels.data() + size_t(bottomUp ? height - 1 - y : y) * pitch;
        for (UINT x = 0; x < width; ++x) {
            const auto pixel = row[x];
            Check((pixel >> 24) == 255, "Waiting output is not opaque.");
            if ((pixel & 0xffffff) == 0xffffff) continue;
            Check(std::abs(double(x) + .5 - width / 2.0) <= side / 2 + 1 &&
                std::abs(double(y) + .5 - height / 2.0) <= side / 2 + 1,
                "Artwork escaped its centered 28-percent aspect-fit region.");
            minX = std::min(minX, x); minY = std::min(minY, y);
            maxX = std::max(maxX, x); maxY = std::max(maxY, y);
            ++count;
        }
        for (UINT x = width; x < pitch; ++x) Check(row[x] == guard, "Waiting output overwrote row padding.");
    }
    Check(count > size_t(width) * height / 100, "The centered FaceNow icon is missing.");
    Check(std::abs((minX + maxX + 1) / 2.0 - width / 2.0) <= 1 &&
        std::abs((minY + maxY + 1) / 2.0 - height / 2.0) <= 1, "The FaceNow icon is off center.");
    // The shared 1024-pixel artwork has a 720-pixel painted extent on each axis.
    Check(std::abs((maxX - minX + 1) - side * 720 / 1024) <= 3 &&
        std::abs((maxY - minY + 1) - side * 720 / 1024) <= 3, "The FaceNow icon was stretched or incorrectly scaled.");
    const auto center = pixels[size_t(bottomUp ? height - 1 - height / 2 : height / 2) * pitch + width / 2];
    Check((center & 255) > 180 && ((center >> 8) & 255) < 120 && ((center >> 16) & 255) < 160,
        "The center does not contain the shared purple FaceNow star.");
    for (size_t i = size_t(pitch) * height; i < pixels.size(); ++i)
        Check(pixels[i] == guard, "Waiting output overran its buffer.");
    std::cout << "PASS centered FaceNow waiting artwork " << width << 'x' << height
        << (bottomUp ? " bottom-up" : " top-down") << '\n';
}

int main() {
    try {
        FaceNowFrames::WaitingCanvas canvas;
        for (const auto& size : {std::pair{1920u, 1080u}, {1080u, 1920u}, {1408u, 1408u}, {1152u, 1536u}, {1536u, 1152u}}) {
            Verify(canvas, size.first, size.second, false);
            Verify(canvas, size.first, size.second, true);
        }
        Check(canvas.Configure(0, 1080) == E_INVALIDARG, "Invalid canvas dimensions were accepted.");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
