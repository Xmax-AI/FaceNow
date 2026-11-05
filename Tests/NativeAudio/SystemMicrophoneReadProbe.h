#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
#include "AudioTimelineBuffer.h"
typedef struct MicrophoneReadProbe MicrophoneReadProbe;
typedef struct { uint64_t frames; uint64_t nonzero; double energy; float peak; OSStatus status; } MicrophoneReadResult;
MicrophoneReadProbe * MicrophoneReadProbeStart(void);
OSStatus MicrophoneReadProbeStatus(MicrophoneReadProbe *probe);
MicrophoneReadResult MicrophoneReadProbeFinish(MicrophoneReadProbe *probe);
