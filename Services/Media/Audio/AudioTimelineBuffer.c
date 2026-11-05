// Copyright (c) 2026 XMAX.AI PTE. LTD.
#include "AudioTimelineBuffer.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mach/mach_time.h>

#define CAPACITY 32768u
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Audio callbacks require lock-free 64-bit atomics");

typedef struct {
    _Atomic uint64_t stamp;
    _Atomic uint64_t stereo;
    _Atomic uint64_t epoch;
} Slot;

struct AudioTimelineBuffer {
    Slot slots[CAPACITY];
    _Atomic uint64_t epoch;
    double sampleRate;
    double ticksToSeconds;
};

AudioTimelineBuffer* AudioTimelineBufferCreate(double sampleRate) {
    if (!isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 192000) return NULL;
    AudioTimelineBuffer* buffer = calloc(1, sizeof(*buffer));
    if (!buffer) return NULL;
    buffer->sampleRate = sampleRate;
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    buffer->ticksToSeconds = (double)info.numer / (double)info.denom / 1e9;
    for (uint32_t i = 0; i < CAPACITY; ++i) {
        atomic_init(&buffer->slots[i].stamp, 0);
        atomic_init(&buffer->slots[i].stereo, 0);
        atomic_init(&buffer->slots[i].epoch, 0);
    }
    atomic_init(&buffer->epoch, 1);
    return buffer;
}

void AudioTimelineBufferDestroy(AudioTimelineBuffer* buffer) { free(buffer); }
void AudioTimelineBufferReset(AudioTimelineBuffer* buffer) { if (buffer) atomic_fetch_add(&buffer->epoch, 1); }

void AudioTimelineBufferWrite(AudioTimelineBuffer* buffer, uint64_t first, const float* samples, uint32_t frames, float gain) {
    if (!buffer || !samples || frames > CAPACITY || first > UINT64_MAX - frames) return;
    uint64_t epoch = atomic_load(&buffer->epoch);
    for (uint32_t i = 0; i < frames; ++i) {
        Slot* slot = &buffer->slots[(first + i) % CAPACITY];
        float left = samples[i * 2] * gain, right = samples[i * 2 + 1] * gain;
        float stereo[2] = { isfinite(left) ? left : 0, isfinite(right) ? right : 0 };
        uint64_t bits;
        memcpy(&bits, stereo, sizeof(bits));
        atomic_store(&slot->stamp, UINT64_MAX);
        atomic_store(&slot->stereo, bits);
        atomic_store(&slot->epoch, epoch);
        atomic_store(&slot->stamp, first + i);
    }
}

uint32_t AudioTimelineBufferRead(AudioTimelineBuffer* buffer, uint64_t first, float* samples, uint32_t frames) {
    if (!samples || frames > CAPACITY) return 0;
    memset(samples, 0, (size_t)frames * 2 * sizeof(float));
    if (!buffer || frames > CAPACITY || first > UINT64_MAX - frames) return 0;
    uint64_t epoch = atomic_load(&buffer->epoch);
    uint32_t found = 0;
    for (uint32_t i = 0; i < frames; ++i) {
        Slot* slot = &buffer->slots[(first + i) % CAPACITY];
        uint64_t stamp = atomic_load(&slot->stamp);
        uint64_t slotEpoch = atomic_load(&slot->epoch);
        uint64_t bits = atomic_load(&slot->stereo);
        if (stamp == first + i && slotEpoch == epoch && atomic_load(&slot->stamp) == stamp &&
            atomic_load(&slot->epoch) == epoch && atomic_load(&buffer->epoch) == epoch) {
            memcpy(samples + i * 2, &bits, sizeof(bits));
            ++found;
        }
    }
    return found;
}

void AudioTimelineBufferSchedule(AudioTimelineBuffer* buffer, double seconds, const float* samples, uint32_t frames) {
    if (!buffer || !isfinite(seconds) || seconds < 0 || seconds * buffer->sampleRate > (double)INT64_MAX) return;
    AudioTimelineBufferWrite(buffer, (uint64_t)llround(seconds * buffer->sampleRate), samples, frames, 1);
}

OSStatus AudioTimelineBufferRender(void* context, AudioUnitRenderActionFlags* flags, const AudioTimeStamp* timeStamp,
                                  UInt32 bus, UInt32 frames, AudioBufferList* output) {
    (void)bus;
    AudioTimelineBuffer* buffer = context;
    if (!output) return kAudio_ParamError;
    for (UInt32 i = 0; i < output->mNumberBuffers; ++i) {
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
    if (!buffer || !timeStamp || !(timeStamp->mFlags & kAudioTimeStampHostTimeValid) || output->mNumberBuffers != 1 ||
        output->mBuffers[0].mDataByteSize < (size_t)frames * 2 * sizeof(float)) {
        if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }
    uint64_t first = (uint64_t)llround((double)timeStamp->mHostTime * buffer->ticksToSeconds * buffer->sampleRate);
    uint32_t count = AudioTimelineBufferRead(buffer, first, output->mBuffers[0].mData, frames);
    if (!count && flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}
