// Loads only the packaged plug-in in this process; does not register it with Core Audio.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static OSStatus storage(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef* value) {
    (void)host; (void)key; *value = NULL; return noErr;
}

static void verifyBundle(const char* path) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)path, strlen(path), true);
    CFPlugInRef plugin = CFPlugInCreate(NULL, url);
    assert(plugin != NULL);
    CFBundleRef bundle = CFPlugInGetBundle(plugin);
    CFArrayRef factories = CFPlugInFindFactoriesForPlugInTypeInPlugIn(kAudioServerPlugInTypeUUID, plugin);
    assert(factories != NULL && CFArrayGetCount(factories) == 1);
    AudioServerPlugInDriverRef driver = CFPlugInInstanceCreate(NULL, CFArrayGetValueAtIndex(factories, 0), kAudioServerPlugInTypeUUID);
    assert(driver != NULL);
    struct AudioServerPlugInHostInterface host = {0}; host.CopyFromStorage = storage;
    assert((*driver)->Initialize(driver, &host) == noErr);
    AudioObjectPropertyAddress property = { kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, 0 };
    AudioObjectID devices[2] = {0}; UInt32 size = sizeof(devices);
    assert((*driver)->GetPropertyDataSize(driver, kAudioObjectPlugInObject, 0, &property, 0, NULL, &size) == noErr && size == sizeof(devices));
    assert((*driver)->GetPropertyData(driver, kAudioObjectPlugInObject, 0, &property, 0, NULL, size, &size, devices) == noErr && size == sizeof(devices));
    AudioObjectID device = devices[0], writer = devices[1];
    assert(device != 0 && writer != 0 && device != writer);
    property.mSelector = kAudioDevicePropertyDeviceUID;
    CFStringRef uid = NULL; size = sizeof(uid);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &uid) == noErr);
    assert(CFEqual(uid, CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("FaceNowMicrophoneUID"))));
    size = sizeof(uid);
    assert((*driver)->GetPropertyData(driver, writer, 0, &property, 0, NULL, size, &size, &uid) == noErr);
    assert(CFEqual(uid, CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("FaceNowWriterUID"))));
    property.mSelector = kAudioObjectPropertyName;
    CFStringRef name = NULL; size = sizeof(name);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &name) == noErr);
    assert(CFEqual(name, CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("FaceNowMicrophoneName"))));
    CFRelease(name);
    assert((*driver)->GetPropertyData(driver, writer, 0, &property, 0, NULL, size, &size, &name) == noErr);
    assert(CFEqual(name, CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("FaceNowSpeakerName"))));
    CFRelease(name);
    property.mSelector = kAudioPlugInPropertyTranslateUIDToDevice;
    AudioObjectID translated = 0; size = sizeof(translated);
    assert((*driver)->GetPropertyData(driver, kAudioObjectPlugInObject, 0, &property, sizeof(uid), &uid,
        size, &size, &translated) == noErr && translated == writer);
    property.mSelector = kAudioDevicePropertyIsHidden;
    UInt32 hidden = 0; size = sizeof(hidden);
    assert((*driver)->GetPropertyData(driver, writer, 0, &property, 0, NULL, size, &size, &hidden) == noErr && hidden == 1);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &hidden) == noErr && hidden == 0);
    property.mSelector = kAudioDevicePropertyStreams;
    property.mScope = kAudioObjectPropertyScopeOutput;
    assert((*driver)->GetPropertyDataSize(driver, device, 0, &property, 0, NULL, &size) == noErr && size == 0);
    property.mScope = kAudioObjectPropertyScopeInput;
    assert((*driver)->GetPropertyDataSize(driver, writer, 0, &property, 0, NULL, &size) == noErr && size == 0);
    AudioObjectID inputStream = 0, outputStream = 0; size = sizeof(inputStream);
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL, size, &size, &inputStream) == noErr && size == sizeof(inputStream));
    property.mScope = kAudioObjectPropertyScopeOutput;
    assert((*driver)->GetPropertyData(driver, writer, 0, &property, 0, NULL, size, &size, &outputStream) == noErr && size == sizeof(outputStream));
    assert((*driver)->StartIO(driver, device, 1) == noErr);
    assert((*driver)->StartIO(driver, writer, 2) == noErr);
    float sent[960], received[960];
    for (int i = 0; i < 960; ++i) sent[i] = i / 1000.0f;
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = 4096; cycle.mInputTime.mSampleTime = 4608;
    assert((*driver)->DoIOOperation(driver, writer, outputStream, 2, kAudioServerPlugInIOOperationWriteMix, 480, &cycle, sent, NULL) == noErr);
    assert((*driver)->DoIOOperation(driver, device, inputStream, 2, kAudioServerPlugInIOOperationReadInput, 480, &cycle, received, NULL) == noErr);
    assert(memcmp(sent, received, sizeof(sent)) == 0);
    assert((*driver)->StopIO(driver, writer, 2) == noErr);
    assert((*driver)->StopIO(driver, device, 1) == noErr);
    puts("PASS: packaged CFPlugIn, visible input-only microphone, hidden UID writer, two-device PCM loopback");
    CFRelease(factories); CFRelease(plugin); CFRelease(url);
}

int main(int argc, char** argv) {
    assert(argc == 2 || argc == 3);
    CFPlugInRef plugins[2] = {NULL, NULL};
    for (int i = 1; i < argc; ++i) {
        CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)argv[i], strlen(argv[i]), true);
        plugins[i-1] = CFPlugInCreate(NULL, url);
        assert(plugins[i-1] != NULL);
        CFRelease(url);
    }
    if (argc == 3) {
        CFArrayRef factories = CFPlugInFindFactoriesForPlugInType(kAudioServerPlugInTypeUUID);
        assert(factories && CFArrayGetCount(factories) == 2);
        CFRelease(factories);
        CFTypeRef firstUID = CFBundleGetValueForInfoDictionaryKey(CFPlugInGetBundle(plugins[0]), CFSTR("FaceNowMicrophoneUID"));
        CFTypeRef secondUID = CFBundleGetValueForInfoDictionaryKey(CFPlugInGetBundle(plugins[1]), CFSTR("FaceNowMicrophoneUID"));
        assert(!CFEqual(firstUID, secondUID));
    }
    for (int i = 1; i < argc; ++i) verifyBundle(argv[i]);
    for (int i = 1; i < argc; ++i) CFRelease(plugins[i-1]);
    return 0;
}
