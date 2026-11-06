// Copyright (c) 2026 XMAX.AI PTE. LTD.
#include "AudioTimelineBuffer.h"
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mach/mach_time.h>

#define CAPACITY 524288u
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Audio callbacks require lock-free 64-bit atomics");
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio callbacks require lock-free delay updates");

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
    /// The worker-written target hold in sample frames, limited to two seconds.
    _Atomic uint32_t targetDelay;
    /// Render-owned read positions; only the serialized AudioUnit callback accesses these fields.
    uint32_t currentDelay;
    uint32_t previousDelay;
    /// Remaining crossfade frames; source samples remain fixed on their automatic timeline.
    uint32_t fadeRemaining;
    /// The last reset observed by the render callback, preventing crossfades into old sessions.
    uint64_t renderEpoch;
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
    atomic_init(&buffer->targetDelay, 0);
    return buffer;
}

void AudioTimelineBufferDestroy(AudioTimelineBuffer* buffer) { free(buffer); }
void AudioTimelineBufferReset(AudioTimelineBuffer* buffer) { if (buffer) atomic_fetch_add(&buffer->epoch, 1); }

void AudioTimelineBufferSetPlaybackDelay(AudioTimelineBuffer* buffer, double seconds) {
    if (!buffer) return;
    double delay = isfinite(seconds) ? fmin(2, fmax(0, seconds)) : 0;
    atomic_store(&buffer->targetDelay, (uint32_t)llround(delay * buffer->sampleRate));
}

/// Reads one timestamp-tagged stereo slot; epoch changes and missing history always produce silence.
static bool ReadStereo(AudioTimelineBuffer* buffer, uint64_t frame, uint64_t epoch, float* samples) {
    Slot* slot = &buffer->slots[frame % CAPACITY];
    uint64_t stamp = atomic_load(&slot->stamp);
    uint64_t slotEpoch = atomic_load(&slot->epoch);
    uint64_t bits = atomic_load(&slot->stereo);
    if (stamp != frame || slotEpoch != epoch || atomic_load(&slot->stamp) != stamp ||
        atomic_load(&slot->epoch) != epoch || atomic_load(&buffer->epoch) != epoch) {
        samples[0] = samples[1] = 0;
        return false;
    }
    memcpy(samples, &bits, sizeof(bits));
    return true;
}

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
        found += ReadStereo(buffer, first + i, epoch, samples + i * 2);
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
        !output->mBuffers[0].mData ||
        output->mBuffers[0].mDataByteSize < (size_t)frames * 2 * sizeof(float)) {
        if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }
    uint64_t first = (uint64_t)llround((double)timeStamp->mHostTime * buffer->ticksToSeconds * buffer->sampleRate);
    if (frames > CAPACITY || first > UINT64_MAX - frames) {
        if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }
    uint64_t epoch = atomic_load(&buffer->epoch);
    uint32_t target = atomic_load(&buffer->targetDelay);
    uint32_t fadeFrames = (uint32_t)llround(buffer->sampleRate * 0.02);
    if (buffer->renderEpoch != epoch) {
        buffer->renderEpoch = epoch;
        buffer->currentDelay = buffer->previousDelay = target;
        buffer->fadeRemaining = 0;
    } else if (target != buffer->currentDelay) {
        buffer->previousDelay = buffer->currentDelay;
        buffer->currentDelay = target;
        buffer->fadeRemaining = fadeFrames;
    }
    uint32_t count = 0;
    float* samples = output->mBuffers[0].mData;
    for (uint32_t i = 0; i < frames; ++i) {
        float current[2] = {0, 0}, previous[2] = {0, 0};
        uint64_t frame = first + i;
        bool found = frame >= buffer->currentDelay &&
            ReadStereo(buffer, frame - buffer->currentDelay, epoch, current);
        if (buffer->fadeRemaining) {
            bool hadPrevious = frame >= buffer->previousDelay &&
                ReadStereo(buffer, frame - buffer->previousDelay, epoch, previous);
            float progress = 1.0f - (float)buffer->fadeRemaining / (float)fadeFrames;
            samples[i * 2] = previous[0] * (1 - progress) + current[0] * progress;
            samples[i * 2 + 1] = previous[1] * (1 - progress) + current[1] * progress;
            --buffer->fadeRemaining;
            found = found || hadPrevious;
        } else {
            samples[i * 2] = current[0];
            samples[i * 2 + 1] = current[1];
        }
        count += found;
    }
    if (!count && flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}
