// Copyright (c) 2026 XMAX.AI PTE. LTD.
#include "EchoCanceller.h"
#include <mach/mach_time.h>
#include <math.h>
#include <speex/speex_echo.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define HISTORY_FRAMES 32768u
#define FILTER_SAMPLES 9600
// Leave a complete packet of headroom once the tap falls behind the microphone.
#define LEAD_STEP_SAMPLES FACENOW_ECHO_FRAME_SAMPLES
#define MAX_REFERENCE_LEAD_SAMPLES (FACENOW_ECHO_FRAME_SAMPLES * 3u)
#define MIN_REFERENCE_SAMPLES (FACENOW_ECHO_FRAME_SAMPLES * 95 / 100)

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Audio callbacks require lock-free 64-bit atomics");

struct FaceNowEchoCanceller {
    // Playback writes packed stereo PCM16 and a frame tag in the same atomic slot.
    _Atomic uint64_t history[HISTORY_FRAMES];
    _Atomic uint64_t latestEnd;
    _Atomic uint64_t processedPackets;
    double hostTicksToFrames;
    uint64_t nextPlaybackFrame;
    double nextSourceFrame;
    // Only the microphone callback touches the DSP state after creation.
    SpeexEchoState* speex;
    int64_t previousMicrophoneUs;
    uint32_t leadSamples;
    bool continuous;
    uint64_t calibration;
};

FaceNowEchoCanceller* FaceNowEchoCancellerCreate(void) {
    FaceNowEchoCanceller* engine = calloc(1, sizeof(*engine));
    if (!engine) return NULL;
    atomic_init(&engine->latestEnd, 0);
    atomic_init(&engine->processedPackets, 0);
    for (uint32_t i = 0; i < HISTORY_FRAMES; ++i) atomic_init(&engine->history[i], 0);
    engine->speex = speex_echo_state_init_mc(FACENOW_ECHO_FRAME_SAMPLES, FILTER_SAMPLES, 1, 2);
    if (!engine->speex) {
        free(engine);
        return NULL;
    }
    int sampleRate = FACENOW_ECHO_SAMPLE_RATE;
    speex_echo_ctl(engine->speex, SPEEX_ECHO_SET_SAMPLING_RATE, &sampleRate);
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    engine->hostTicksToFrames = (double)timebase.numer / timebase.denom * FACENOW_ECHO_SAMPLE_RATE / 1e9;
    return engine;
}

void FaceNowEchoCancellerDestroy(FaceNowEchoCanceller* engine) {
    if (!engine) return;
    speex_echo_state_destroy(engine->speex);
    free(engine);
}

static int16_t pcm16(float sample) {
    if (!isfinite(sample)) return 0;
    return (int16_t)lrintf(fminf(32767, fmaxf(-32768, sample * 32768)));
}

static int16_t interpolate(const float* samples, uint32_t stride, uint32_t count, double index) {
    uint32_t first = (uint32_t)index;
    uint32_t second = first + 1 < count ? first + 1 : first;
    float a = samples[first * stride];
    return pcm16(a + (samples[second * stride] - a) * (index - first));
}

void FaceNowEchoCancellerFeedPlayback(FaceNowEchoCanceller* engine,
    const AudioBufferList* audio, double sourceRate, uint64_t hostTime) {
    if (audio->mNumberBuffers == 0 || !isfinite(sourceRate) || sourceRate < 8000 || sourceRate > 384000 || hostTime == 0) return;
    const AudioBuffer* left = &audio->mBuffers[0];
    if (!left->mData || left->mNumberChannels == 0) return;
    const float* leftSamples = left->mData;
    uint32_t leftStride = left->mNumberChannels;
    uint32_t frames = left->mDataByteSize / sizeof(float) / leftStride;
    const float* rightSamples = leftSamples;
    uint32_t rightStride = leftStride;
    if (leftStride > 1) {
        rightSamples += 1;
    } else if (audio->mNumberBuffers > 1) {
        const AudioBuffer* right = &audio->mBuffers[1];
        if (right->mData && right->mNumberChannels > 0) {
            rightSamples = right->mData;
            rightStride = right->mNumberChannels;
            uint32_t rightFrames = right->mDataByteSize / sizeof(float) / rightStride;
            frames = frames < rightFrames ? frames : rightFrames;
        }
    }
    if (frames == 0 || frames > 16384) return;

    double first = hostTime * engine->hostTicksToFrames;
    double step = sourceRate / FACENOW_ECHO_SAMPLE_RATE;
    uint64_t frame = (uint64_t)llround(first);
    double index = 0;
    // Use host time for the absolute position and preserve the fractional phase across contiguous blocks.
    if (engine->nextPlaybackFrame && fabs((double)engine->nextPlaybackFrame - first) < 4) {
        frame = engine->nextPlaybackFrame;
        index = engine->nextSourceFrame;
    }
    while (index < frames) {
        uint32_t l = (uint16_t)interpolate(leftSamples, leftStride, frames, index);
        uint32_t r = (uint16_t)interpolate(rightSamples, rightStride, frames, index);
        uint64_t value = ((uint64_t)(uint32_t)frame << 32) | (r << 16) | l;
        atomic_store_explicit(&engine->history[frame & (HISTORY_FRAMES - 1)], value, memory_order_relaxed);
        ++frame;
        index += step;
    }
    engine->nextPlaybackFrame = frame;
    engine->nextSourceFrame = index - frames;
    atomic_store_explicit(&engine->latestEnd, frame, memory_order_release);
}

bool FaceNowEchoCancellerProcess(FaceNowEchoCanceller* engine,
    const int16_t* microphone, int64_t hostTimestampUs, uint64_t calibration, int16_t* result) {
    if (hostTimestampUs < 100000) return false;
    uint64_t microphoneStart = (uint64_t)llround((double)hostTimestampUs * FACENOW_ECHO_SAMPLE_RATE / 1e6);
    uint64_t end = atomic_load_explicit(&engine->latestEnd, memory_order_acquire);
    uint64_t requestedEnd = microphoneStart + FACENOW_ECHO_FRAME_SAMPLES;
    if (end == 0 || end + MAX_REFERENCE_LEAD_SAMPLES < requestedEnd) {
        engine->continuous = false;
        return false;
    }
    uint64_t requiredLead = requestedEnd > end ? requestedEnd - end : 0;
    if (!engine->continuous || engine->calibration != calibration ||
        requiredLead > engine->leadSamples + FACENOW_ECHO_FRAME_SAMPLES - MIN_REFERENCE_SAMPLES) {
        // Move the reference window only when necessary. Shrinking the lead during a
        // healthy run changes the echo path seen by the filter and loses convergence.
        uint32_t newLead = (uint32_t)((requiredLead + LEAD_STEP_SAMPLES - 1) / LEAD_STEP_SAMPLES) * LEAD_STEP_SAMPLES;
        if (engine->leadSamples != newLead) engine->continuous = false;
        engine->leadSamples = newLead;
    }
    uint64_t first = microphoneStart - engine->leadSamples;
    int16_t playback[FACENOW_ECHO_FRAME_SAMPLES * 2] = {0};
    uint32_t found = 0;
    for (uint32_t i = 0; i < FACENOW_ECHO_FRAME_SAMPLES; ++i) {
        uint64_t frame = first + i;
        if (frame >= end || frame + HISTORY_FRAMES <= end) continue;
        uint64_t value = atomic_load_explicit(&engine->history[frame & (HISTORY_FRAMES - 1)], memory_order_relaxed);
        if ((uint32_t)(value >> 32) != (uint32_t)frame || value == 0) continue;
        playback[2 * i] = (int16_t)value;
        playback[2 * i + 1] = (int16_t)(value >> 16);
        ++found;
    }
    if (found < MIN_REFERENCE_SAMPLES) return false;
    if (!engine->continuous || engine->calibration != calibration || llabs(hostTimestampUs - engine->previousMicrophoneUs - 10000) > 1000) {
        speex_echo_state_reset(engine->speex);
    }
    engine->calibration = calibration;
    engine->continuous = true;
    engine->previousMicrophoneUs = hostTimestampUs;
    speex_echo_cancellation(engine->speex, microphone, playback, result);
    atomic_fetch_add_explicit(&engine->processedPackets, 1, memory_order_relaxed);
    return true;
}

uint64_t FaceNowEchoCancellerProcessedPacketCount(const FaceNowEchoCanceller* engine) {
    return atomic_load_explicit(&engine->processedPackets, memory_order_relaxed);
}
