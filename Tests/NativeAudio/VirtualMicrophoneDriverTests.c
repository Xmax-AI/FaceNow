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
    static struct AudioServerPlugInHostInterface host = {0};
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

    address.mSelector = kAudioSelectorControlPropertyItemName;
    address.mScope = kAudioObjectPropertyScopeGlobal;
    UInt32 item = 0;
    CFStringRef inputSourceName = NULL;
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_DataSource_Input_Master, 0,
        &address, sizeof(item), &item, sizeof(inputSourceName), &size, &inputSourceName) == noErr);
    assert(size == sizeof(inputSourceName) && CFEqual(inputSourceName, CFSTR(FACENOW_MICROPHONE_NAME)));
    CFRelease(inputSourceName);
}

static UInt32 deviceValue(AudioObjectID device, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {selector, scope, 0};
    UInt32 value = UINT32_MAX, size = sizeof(value);
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, device, 0, &address, 0, NULL,
        size, &size, &value) == noErr && size == sizeof(value));
    return value;
}

static void assertObjects(AudioObjectID device, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope,
                          const AudioObjectID* expected, UInt32 count) {
    AudioObjectPropertyAddress address = {selector, scope, 0};
    UInt32 size = 0;
    assert(FaceNowMicrophone_GetPropertyDataSize(gAudioServerPlugInDriverRef, device, 0, &address, 0, NULL, &size) == noErr);
    assert(size == count * sizeof(AudioObjectID));
    AudioObjectID values[12] = {0};
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, device, 0, &address, 0, NULL,
        sizeof(values), &size, values) == noErr && size == count * sizeof(AudioObjectID));
    for (UInt32 i = 0; i < count; ++i) assert(values[i] == expected[i]);
    for (UInt32 i = 0; i < count; ++i) {
        assert(deviceValue(values[i], kAudioObjectPropertyOwner, kAudioObjectPropertyScopeGlobal) == device);
    }
    if (count == 0) {
        assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, device, 0, &address, 0, NULL,
            0, &size, NULL) == noErr && size == 0);
    }
}

static void testInputOnlyTopology(void) {
    AudioObjectPropertyAddress address = {kAudioObjectPropertyOwnedObjects, kAudioObjectPropertyScopeGlobal, 0};
    AudioObjectID owned[3] = {0}; UInt32 size = sizeof(owned);
    assert(FaceNowMicrophone_GetPropertyDataSize(gAudioServerPlugInDriverRef, kObjectID_PlugIn, 0, &address, 0, NULL, &size) == noErr && size == sizeof(owned));
    assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_PlugIn, 0, &address, 0, NULL, size, &size, owned) == noErr);
    assert(owned[0] == kObjectID_Box && owned[1] == kObjectID_Device && owned[2] == kObjectID_Device_Writer);
    address.mSelector = kAudioPlugInPropertyTranslateUIDToDevice;
    const CFStringRef uids[] = {CFSTR(kDevice_UID), CFSTR(kWriter_UID), CFSTR("not-a-device")};
    const AudioObjectID expected[] = {kObjectID_Device, kObjectID_Device_Writer, kAudioObjectUnknown};
    for (int i = 0; i < 3; ++i) {
        AudioObjectID device = 0; size = sizeof(device);
        assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_PlugIn, 0, &address,
            sizeof(uids[i]), &uids[i], size, &size, &device) == noErr && device == expected[i]);
    }
    assert(deviceValue(kObjectID_Device, kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal) == 0);
    assert(deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal) == 1);
    assert(deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput) == 0);
    assert(deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, kAudioObjectPropertyScopeOutput) == 0);
    UInt32 domain = deviceValue(kObjectID_Device, kAudioDevicePropertyClockDomain, kAudioObjectPropertyScopeGlobal);
    assert(domain != 0 && domain == deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyClockDomain, kAudioObjectPropertyScopeGlobal));
    const AudioObjectID input[] = {kObjectID_Stream_Input};
    const AudioObjectID output[] = {kObjectID_Stream_Output};
    const AudioObjectID inputOwned[] = {4, 5, 6, 7};
    const AudioObjectID writerOwned[] = {8, 9, 10, 11, 12};
    assertObjects(kObjectID_Device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, input, 1);
    assertObjects(kObjectID_Device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeGlobal, input, 1);
    assertObjects(kObjectID_Device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, NULL, 0);
    assertObjects(kObjectID_Device_Writer, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, output, 1);
    assertObjects(kObjectID_Device_Writer, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, NULL, 0);
    assertObjects(kObjectID_Device, kAudioObjectPropertyOwnedObjects, kAudioObjectPropertyScopeGlobal, inputOwned, 4);
    assertObjects(kObjectID_Device_Writer, kAudioObjectPropertyOwnedObjects, kAudioObjectPropertyScopeGlobal, writerOwned, 5);
    assertObjects(kObjectID_Device, kAudioObjectPropertyControlList, kAudioObjectPropertyScopeGlobal, inputOwned + 1, 3);
    assertObjects(kObjectID_Device_Writer, kAudioObjectPropertyControlList, kAudioObjectPropertyScopeGlobal, writerOwned + 1, 4);
    Boolean willDo = true, inPlace = false;
    assert(FaceNowMicrophone_WillDoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, 1,
        kAudioServerPlugInIOOperationWriteMix, &willDo, &inPlace) == noErr && !willDo);
    assert(FaceNowMicrophone_WillDoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 1,
        kAudioServerPlugInIOOperationReadInput, &willDo, &inPlace) == noErr && !willDo);
}

static void testActualLoopbackCallbacks(void) {
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    UInt64 anchor = gDevice_AnchorHostTime;
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 3) == noErr);
    assert(gDevice_AnchorHostTime == anchor);
    float input[960], read[960], again[960];
    for (int i = 0; i < 960; ++i) input[i] = (i % 100) / 100.0f;
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = 3000;
    cycle.mInputTime.mSampleTime = 3512;
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Output, 1,
        kAudioServerPlugInIOOperationWriteMix, 480, &cycle, input, NULL) == kAudioHardwareIllegalOperationError);
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, kObjectID_Stream_Output, 3,
        kAudioServerPlugInIOOperationWriteMix, 480, &cycle, input, NULL) == noErr);
    assert(FaceNowMicrophone_PerformDeviceConfigurationChange(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 48000, NULL) == noErr);
    // A second conference reader must neither reset the shared clock nor erase generated audio.
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 2) == noErr);
    assert(gDevice_AnchorHostTime == anchor);
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 1,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL) == noErr);
    assert(memcmp(input, read, sizeof(read)) == 0);
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 2,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, again, NULL) == noErr);
    assert(memcmp(read, again, sizeof(read)) == 0);
    cycle.mInputTime.mSampleTime += 524288;
    assert(FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 2,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL) == noErr);
    for (int i = 0; i < 960; ++i) assert(read[i] == 0);
    cycle.mInputTime.mSampleTime = 3512;
    gMute_Input_Master_Value = true;
    FaceNowMicrophone_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input, 1,
        kAudioServerPlugInIOOperationReadInput, 480, &cycle, read, NULL);
    for (int i = 0; i < 960; ++i) assert(read[i] == 0);
    gMute_Input_Master_Value = false;
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 3) == noErr);
    assert(deviceValue(kObjectID_Device, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal) == 1);
    assert(deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal) == 0);
    assert(AudioTimelineBufferRead(gLoopback, 3000, read, 480) == 0);
    assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 3) == noErr);
    assert(gDevice_AnchorHostTime == anchor);
    assert(AudioTimelineBufferRead(gLoopback, 3000, read, 480) == 0);
    gDevice_AnchorHostTime -= (UInt64)(10 * 48000 * gDevice_HostTicksPerFrame);
    Float64 sample; UInt64 host, seed;
    assert(FaceNowMicrophone_GetZeroTimeStamp(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 3, &sample, &host, &seed) == noErr);
    assert(sample > 9 * 48000);
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 2) == noErr);
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 2) == kAudioHardwareIllegalOperationError);
    assert(deviceValue(kObjectID_Device_Writer, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal) == 1);
    assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device_Writer, 3) == noErr);
    assert(gDevice_IOIsRunning == 0);
}

static void testSharedSampleRate(void) {
    const AudioObjectID devices[] = {kObjectID_Device, kObjectID_Device_Writer};
    for (int i = 0; i < 2; ++i) {
        assert(FaceNowMicrophone_PerformDeviceConfigurationChange(gAudioServerPlugInDriverRef, devices[i], 44100, NULL) == noErr);
        AudioObjectPropertyAddress address = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, 0};
        for (int j = 0; j < 2; ++j) {
            Float64 rate = 0; UInt32 size = sizeof(rate);
            assert(FaceNowMicrophone_GetPropertyData(gAudioServerPlugInDriverRef, devices[j], 0, &address,
                0, NULL, size, &size, &rate) == noErr && rate == 44100);
        }
        assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, devices[1-i], 1) == noErr);
        assert(FaceNowMicrophone_PerformDeviceConfigurationChange(gAudioServerPlugInDriverRef, devices[i], 48000, NULL) == kAudioHardwareIllegalOperationError);
        assert(gDevice_SampleRate == 44100);
        assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, devices[1-i], 1) == noErr);
        assert(FaceNowMicrophone_PerformDeviceConfigurationChange(gAudioServerPlugInDriverRef, devices[i], 48000, NULL) == noErr);
    }
}

static AudioTimelineBuffer* concurrentRing;

static void* endpointLifecycle(void* context) {
    AudioObjectID device = (AudioObjectID)(uintptr_t)context;
    for (int i = 0; i < 1000; ++i) {
        assert(FaceNowMicrophone_StartIO(gAudioServerPlugInDriverRef, device, 1) == noErr);
        Float64 sample; UInt64 host, seed;
        assert(FaceNowMicrophone_GetZeroTimeStamp(gAudioServerPlugInDriverRef, device, 1, &sample, &host, &seed) == noErr);
        assert(FaceNowMicrophone_StopIO(gAudioServerPlugInDriverRef, device, 1) == noErr);
    }
    return NULL;
}

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
    testInputOnlyTopology();
    testActualLoopbackCallbacks();
    testSharedSampleRate();
    pthread_t inputLifecycle, writerLifecycle;
    pthread_create(&inputLifecycle, NULL, endpointLifecycle, (void*)(uintptr_t)kObjectID_Device);
    pthread_create(&writerLifecycle, NULL, endpointLifecycle, (void*)(uintptr_t)kObjectID_Device_Writer);
    pthread_join(inputLifecycle, NULL);
    pthread_join(writerLifecycle, NULL);
    assert(gDevice_IOIsRunning == 0 && gInput_IOIsRunning == 0 && gWriter_IOIsRunning == 0);
    concurrentRing = AudioTimelineBufferCreate(48000);
    pthread_t writeThread, readThread;
    pthread_create(&writeThread, NULL, writer, NULL);
    pthread_create(&readThread, NULL, reader, NULL);
    pthread_join(writeThread, NULL); pthread_join(readThread, NULL);
    AudioTimelineBufferDestroy(concurrentRing);
    puts("PASS: input-only device, hidden UID writer, stream ownership, shared clock/rate, 512-frame loopback, multiple readers, restart silence, atomic ring");
    return 0;
}
