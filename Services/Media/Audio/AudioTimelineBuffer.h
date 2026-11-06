// Copyright (c) 2026 XMAX.AI PTE. LTD.
#pragma once
#include <stdint.h>
#include <AudioUnit/AudioUnit.h>

/// An owned, fixed-capacity stereo Float32 timeline; one writer and concurrent readers.
typedef struct AudioTimelineBuffer AudioTimelineBuffer;
/// Allocates outside the audio callback. The sample rate remains fixed for this instance.
AudioTimelineBuffer* _Nullable AudioTimelineBufferCreate(double sampleRate);
/// Releases after the AudioUnit and its callbacks have stopped.
void AudioTimelineBufferDestroy(AudioTimelineBuffer* _Nullable buffer);
/// Invalidates queued samples immediately without reallocating storage.
void AudioTimelineBufferReset(AudioTimelineBuffer* _Nullable buffer);
/// Sets an additional 0...2000 ms playback delay without moving queued samples; invalid values select zero.
/// One serialized render callback crossfades delay changes over 20 ms. Direct reads remain unshifted.
void AudioTimelineBufferSetPlaybackDelay(AudioTimelineBuffer* _Nullable buffer, double seconds);
/// Stores interleaved stereo at an absolute sample index; frames beyond capacity are rejected.
void AudioTimelineBufferWrite(AudioTimelineBuffer* _Nullable buffer, uint64_t firstFrame, const float* _Nullable samples, uint32_t frames, float gain);
/// Reads exact tagged slots. Missing, expired, or concurrently replaced samples become silence.
uint32_t AudioTimelineBufferRead(AudioTimelineBuffer* _Nullable buffer, uint64_t firstFrame, float* _Nullable samples, uint32_t frames);
/// Maps host seconds to this buffer's sample clock and copies a packet outside the render callback.
void AudioTimelineBufferSchedule(AudioTimelineBuffer* _Nullable buffer, double hostSeconds, const float* _Nullable samples, uint32_t frames);
/// An allocation-free, lock-free AUHAL render callback; one serialized output callback per buffer.
OSStatus AudioTimelineBufferRender(void* _Nonnull context, AudioUnitRenderActionFlags* _Nonnull flags, const AudioTimeStamp* _Nonnull timeStamp,
                                  UInt32 bus, UInt32 frames, AudioBufferList* _Nullable output);
