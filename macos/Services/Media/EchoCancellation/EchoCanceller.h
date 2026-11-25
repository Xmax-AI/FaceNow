// Copyright (c) 2026 XMAX.AI PTE. LTD.
#pragma once

#include <CoreAudio/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

#define FACENOW_ECHO_FRAME_SAMPLES 480
#define FACENOW_ECHO_SAMPLE_RATE 48000

typedef struct FaceNowEchoCanceller FaceNowEchoCanceller;

FaceNowEchoCanceller* _Nullable FaceNowEchoCancellerCreate(void);
void FaceNowEchoCancellerDestroy(FaceNowEchoCanceller* _Nullable engine);

/// Copies Float32 playback PCM to a bounded history using the tap's host timestamp.
/// The tap callback is the single writer. The microphone queue is the single reader.
void FaceNowEchoCancellerFeedPlayback(FaceNowEchoCanceller* _Nonnull engine,
    const AudioBufferList* _Nonnull audio, double sourceRate, uint64_t hostTime);

/// Processes a 10 ms mono PCM16 microphone frame without changing its sample count.
/// Returns false if matching playback data is unavailable so the caller can pass through the input.
bool FaceNowEchoCancellerProcess(FaceNowEchoCanceller* _Nonnull engine,
    const int16_t* _Nonnull microphone, int64_t hostTimestampUs, uint64_t calibration, int16_t* _Nonnull result);

/// Counts microphone packets with a matched playback reference without inspecting audio content.
uint64_t FaceNowEchoCancellerProcessedPacketCount(const FaceNowEchoCanceller* _Nonnull engine);
