// Copyright (c) 2026 XMAX.AI PTE. LTD.
#include "../../Services/Media/EchoCancellation/EchoCanceller.h"
#include <assert.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>

#define FRAME_SAMPLES FACENOW_ECHO_FRAME_SAMPLES
#define BLOCK_COUNT 900
#define ECHO_DELAY_SAMPLES 1344

static float source[FRAME_SAMPLES * BLOCK_COUNT];

static void fillPlayback(void) {
    uint32_t seed = 775923;
    float smoothed = 0;
    for (int i = 0; i < FRAME_SAMPLES * BLOCK_COUNT; ++i) {
        seed = seed * 1664525u + 1013904223u;
        float noise = (float)(seed >> 16) / 32768 - 1;
        smoothed = 0.58f * smoothed + 0.42f * noise;
        source[i] = 0.6f * smoothed;
    }
}

static void feedPlayback(
    FaceNowEchoCanceller* engine, int frameNumber, int64_t startUs, mach_timebase_info_data_t timebase
) {
    AudioBufferList playback = {
        .mNumberBuffers = 1,
        .mBuffers = {{.mNumberChannels = 1, .mDataByteSize = FRAME_SAMPLES * sizeof(float),
            .mData = source + frameNumber * FRAME_SAMPLES}},
    };
    uint64_t ticks = llround((startUs + 10000 * frameNumber) * 1000.0 * timebase.denom / timebase.numer);
    FaceNowEchoCancellerFeedPlayback(engine, &playback, FACENOW_ECHO_SAMPLE_RATE, ticks);
}

int main(void) {
    const int64_t startUs = 60000000;
    FaceNowEchoCanceller* engine = FaceNowEchoCancellerCreate();
    assert(engine);
    fillPlayback();
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);

    int queuedPlaybackFrame = 0;
    double inputEnergy = 0;
    double outputEnergy = 0;
    int16_t microphone[FRAME_SAMPLES] = {0};
    int16_t filtered[FRAME_SAMPLES] = {0};
    assert(!FaceNowEchoCancellerProcess(engine, microphone, startUs, 0, filtered));

    for (int block = 0; block < BLOCK_COUNT; ++block) {
        // Periodically deliver one playback packet just after the corresponding microphone packet.
        // The next IO cycle catches up, as it does with independent Core Audio callbacks.
        int newestPlaybackFrame = block % 5 == 2 ? block - 1 : block;
        while (queuedPlaybackFrame <= newestPlaybackFrame) {
            feedPlayback(engine, queuedPlaybackFrame++, startUs, timebase);
        }
        for (int i = 0; i < FRAME_SAMPLES; ++i) {
            int index = (block * FRAME_SAMPLES + i) - ECHO_DELAY_SAMPLES;
            microphone[i] = index >= 0 ? lrintf(source[index] * 18000) : 0;
        }
        assert(FaceNowEchoCancellerProcess(engine, microphone, startUs + block * 10000, 0, filtered));
        if (block >= BLOCK_COUNT - 100) {
            for (int i = 0; i < FRAME_SAMPLES; ++i) {
                inputEnergy += (double)microphone[i] * microphone[i];
                outputEnergy += (double)filtered[i] * filtered[i];
            }
        }
    }

    double attenuation = 10 * log10(inputEnergy / outputEnergy);
    assert(attenuation > 15);
    assert(FaceNowEchoCancellerProcessedPacketCount(engine) == BLOCK_COUNT);
    assert(!FaceNowEchoCancellerProcess(engine, microphone, startUs + (BLOCK_COUNT + 5) * 10000, 0, filtered));
    printf("Playback scheduling jitter: %d packets processed, %.1f dB echo attenuation\n", BLOCK_COUNT, attenuation);
    FaceNowEchoCancellerDestroy(engine);
    return 0;
}
