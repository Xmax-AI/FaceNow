#include "SystemMicrophoneReadProbe.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
struct MicrophoneReadProbe { AudioDeviceID device; AudioDeviceIOProcID proc; MicrophoneReadResult result; };
static OSStatus readFrames(AudioDeviceID device, const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    MicrophoneReadProbe *probe = context;
    if (input) for (UInt32 b=0; b<input->mNumberBuffers; b++) {
        const AudioBuffer *buffer=&input->mBuffers[b];
        if (!buffer->mData) continue;
        const float *values=buffer->mData;
        UInt32 count=buffer->mDataByteSize/sizeof(float);
        probe->result.frames+=count;
        for (UInt32 i=0; i<count; i++) {
            float value=values[i];
            if (!isfinite(value)) continue;
            float magnitude=fabsf(value);
            if (magnitude>probe->result.peak) probe->result.peak=magnitude;
            if (magnitude>0.001f) probe->result.nonzero++;
            probe->result.energy+=(double)value*value;
        }
    }
    if (output) for (UInt32 b=0; b<output->mNumberBuffers; b++) if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    return noErr;
}
MicrophoneReadProbe *MicrophoneReadProbeStart(void) {
    MicrophoneReadProbe *probe=calloc(1,sizeof(*probe));
    CFStringRef uid=CFSTR("com.xmax.facenow.microphone.device");
    AudioObjectPropertyAddress a={kAudioHardwarePropertyTranslateUIDToDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=sizeof(probe->device);
    probe->result.status=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,sizeof(uid),&uid,&size,&probe->device);
    if (probe->result.status || !probe->device) { if (!probe->result.status) probe->result.status=-1; return probe; }
    a.mSelector=kAudioDevicePropertyDeviceIsRunningSomewhere;
    UInt32 running=0; size=sizeof(running);
    probe->result.status=AudioObjectGetPropertyData(probe->device,&a,0,NULL,&size,&running);
    if (probe->result.status || running) { if (!probe->result.status) probe->result.status=-2; return probe; }
    probe->result.status=AudioDeviceCreateIOProcID(probe->device,readFrames,probe,&probe->proc);
    if (!probe->result.status) probe->result.status=AudioDeviceStart(probe->device,probe->proc);
    return probe;
}
OSStatus MicrophoneReadProbeStatus(MicrophoneReadProbe *probe) { return probe ? probe->result.status : -1; }
MicrophoneReadResult MicrophoneReadProbeFinish(MicrophoneReadProbe *probe) {
    if (probe->proc) { AudioDeviceStop(probe->device,probe->proc); AudioDeviceDestroyIOProcID(probe->device,probe->proc); }
    MicrophoneReadResult result=probe->result;
    free(probe);
    return result;
}
