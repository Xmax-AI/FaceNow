// Loads only the packaged plug-in in this process; does not register it with Core Audio.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static OSStatus storage(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef* value) {
    (void)host; (void)key; *value = NULL; return noErr;
}

int main(int argc, char** argv) {
    assert(argc == 2);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)argv[1], strlen(argv[1]), true);
    CFPlugInRef plugin = CFPlugInCreate(NULL, url);
    assert(plugin != NULL);
    CFArrayRef factories = CFPlugInFindFactoriesForPlugInTypeInPlugIn(kAudioServerPlugInTypeUUID, plugin);
    assert(factories != NULL && CFArrayGetCount(factories) == 1);
    AudioServerPlugInDriverRef driver = CFPlugInInstanceCreate(NULL, CFArrayGetValueAtIndex(factories, 0), kAudioServerPlugInTypeUUID);
    assert(driver != NULL);
    struct AudioServerPlugInHostInterface host = {0}; host.CopyFromStorage = storage;
    assert((*driver)->Initialize(driver, &host) == noErr);
    AudioObjectPropertyAddress property = { kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, 0 };
    AudioObjectID device = 0; UInt32 size = sizeof(device);
    assert((*driver)->GetPropertyData(driver, kAudioObjectPlugInObject, 0, &property, 0, NULL, size, &size, &device) == noErr && device != 0);
    property.mSelector = kAudioDevicePropertyDeviceUID;
    CFStringRef uid = NULL; size = sizeof(uid);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &uid) == noErr);
    assert(CFEqual(uid, CFSTR("com.xmax.facenow.microphone.device")));
    property.mSelector = kAudioDevicePropertyStreams;
    property.mScope = kAudioObjectPropertyScopeInput;
    AudioObjectID inputStream, outputStream; size = sizeof(inputStream);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &inputStream) == noErr);
    property.mScope = kAudioObjectPropertyScopeOutput;
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &outputStream) == noErr);
    assert((*driver)->StartIO(driver, device, 1) == noErr);
    float sent[960], received[960];
    for (int i = 0; i < 960; ++i) sent[i] = i / 1000.0f;
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = 4096; cycle.mInputTime.mSampleTime = 4608;
    assert((*driver)->DoIOOperation(driver, device, outputStream, 1, kAudioServerPlugInIOOperationWriteMix, 480, &cycle, sent, NULL) == noErr);
    assert((*driver)->DoIOOperation(driver, device, inputStream, 2, kAudioServerPlugInIOOperationReadInput, 480, &cycle, received, NULL) == noErr);
    assert(memcmp(sent, received, sizeof(sent)) == 0);
    assert((*driver)->StopIO(driver, device, 1) == noErr);
    puts("PASS: packaged CFPlugIn factory, device UID, input/output streams, real binary PCM loopback");
    CFRelease(factories); CFRelease(plugin); CFRelease(url);
    return 0;
}
