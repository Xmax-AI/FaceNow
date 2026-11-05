// Exercises the actual HAL callbacks in-process; never registers a device or opens a microphone.
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../VirtualMicrophoneDriver/FaceNowMicrophone.c"

static OSStatus storage(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef* data) {
    (void)host; (void)key; *data = NULL; return noErr;
}

static void testProperties(void) {
    struct AudioServerPlugInHostInterface host = {0};
    host.CopyFromStorage = storage;
    AudioServerPlugInHostRef ref = &host;
    assert(FaceNowMicrophone_Initialize(gAudioServerPlugInDriverRef, ref) == noErr);
    AudioObjectPropertyAddress address = { kAudioPlugInPropertyBoxList, kAudioObjectPropertyScopeGlobal, 0 };
    AudioObjectID object = 0; UInt32 size = sizeof(object);
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_PlugIn, 0, &address, 0, NULL, size, &size, &object) == noErr);
    assert(object == kObjectID_Box);
    address.mSelector = kAudioBoxPropertyAcquired;
    UInt32 acquired = 0;
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Box, 0, &address, 0, NULL, 4, &size, &acquired) == noErr && acquired == 1);
    address.mSelector = kAudioDevicePropertyDeviceCanBeDefaultDevice;
    address.mScope = kAudioObjectPropertyScopeOutput;
    UInt32 canDefault = 1;
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &address, 0, NULL, 4, &size, &canDefault) == noErr && canDefault == 0);
    address.mSelector = kAudioDevicePropertyLatency;
    address.mScope = kAudioObjectPropertyScopeInput;
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &address, 0, NULL, 4, &size, &object) == noErr && object == 512);
}

static void testActualLoopbackCallbacks(void) {
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    float input[960], read[960], again[960];
    for (int i = 0; i < 960; ++i) input[i] = (i % 100) / 100.0f;
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = 3000;
    cycle.mInputTime.mSampleTime = 3512;
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Output, 1,
        kAudioServerPlugInIOOperationWriteMix, 480, &cycle, input, NULL) == noErr);
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 2,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL) == noErr);
    assert(memcmp(input, read, sizeof(read)) == 0);
    // Another meeting client reads independently, without consuming the first reader's samples.
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 3,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, again, NULL) == noErr);
    assert(memcmp(read, again, sizeof(read)) == 0);
    // Same ring position in a later revolution must not replay old audio.
    cycle.mInputTime.mSampleTime += 32768;
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 2,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL) == noErr);
    for (int i = 0; i < 960; ++i) assert(read[i] == 0);
    cycle.mInputTime.mSampleTime = 3512;
    gMute_Input_Master_Value = true;
    FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 2,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL);
    for (int i = 0; i < 960; ++i) assert(read[i] == 0);
    gMute_Input_Master_Value = false;
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    assert(AudioTimelineBufferRead(gLoopback, 3000, read, 480) == 0);
    // A late clock query must advance across all missed timestamp periods, not just one.
    gDevice_AnchorHostTime -= (UInt64)(10 * 48000 * gDevice_HostTicksPerFrame);
    Float64 sample; UInt64 host, seed;
    assert(FaceNowMicrophone_GetZeroTimeStamp(gAudioServerPlugInDriverRef, kObjectID_Device, 1, &sample, &host, &seed) == noErr);
    assert(sample > 9 * 48000);
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
}

static AudioTimelineBuffer* concurrentRing;
static void* writer(void* context) {
    (void)context;
    float samples[960];
    for (uint64_t packet = 0; packet < 4000; ++packet) {
        for (int i = 0; i < 480; ++i) { samples[i*2] = (float)packet; samples[i*2+1] = -(float)packet; }
        AudioTimelineBufferWrite(concurrentRing, packet * 480, samples, 480, 1);
    }
    return NULL;
}
static void* reader(void* context) {
    (void)context;
    float samples[960];
    for (uint64_t packet = 0; packet < 4000; ++packet) {
        AudioTimelineBufferRead(concurrentRing, packet * 480, samples, 480);
        for (int i = 0; i < 480; ++i) assert(samples[i*2] == -samples[i*2+1]);
    }
    return NULL;
}

int main(void) {
    AudioTimelineBuffer* sanitizing = AudioTimelineBufferCreate(48000);
    float nonFinite[2] = { NAN, INFINITY }, cleaned[2] = {1, 1};
    AudioTimelineBufferWrite(sanitizing, 9, nonFinite, 1, 1);
    assert(AudioTimelineBufferRead(sanitizing, 9, cleaned, 1) == 1);
    assert(cleaned[0] == 0 && cleaned[1] == 0);
    AudioTimelineBufferReset(sanitizing);
    assert(AudioTimelineBufferRead(sanitizing, 9, cleaned, 1) == 0);
    AudioTimelineBufferDestroy(sanitizing);
    testProperties();
    testActualLoopbackCallbacks();
    concurrentRing = AudioTimelineBufferCreate(48000);
    pthread_t writeThread, readThread;
    pthread_create(&writeThread, NULL, writer, NULL);
    pthread_create(&readThread, NULL, reader, NULL);
    pthread_join(writeThread, NULL); pthread_join(readThread, NULL);
    AudioTimelineBufferDestroy(concurrentRing);
    puts("PASS: HAL properties, 512-frame loopback, concurrent readers, stale silence, mute, restart, clock, atomic ring");
    return 0;
}
